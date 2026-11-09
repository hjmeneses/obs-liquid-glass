// Liquid Glass para OBS Studio (plugin obs-shaderfilter, modo "User-defined shader")
// Dibuja un panel de vidrio con desenfoque, refracción en el bisel, dispersión de color,
// tinte, brillo de borde y sombra sobre la imagen de la fuente o escena donde se aplique.
// Para varios paneles, agrega el filtro varias veces.

uniform float panel_x<
    string label = "Centro X (%)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 100.0; float step = 0.1;
> = 50.0;

uniform float panel_y<
    string label = "Centro Y (%)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 100.0; float step = 0.1;
> = 50.0;

uniform float panel_w<
    string label = "Ancho (%)";
    string widget_type = "slider";
    float minimum = 1.0; float maximum = 100.0; float step = 0.1;
> = 40.0;

uniform float panel_h<
    string label = "Alto (%)";
    string widget_type = "slider";
    float minimum = 1.0; float maximum = 100.0; float step = 0.1;
> = 25.0;

uniform float corner_radius<
    string label = "Radio de esquinas (px)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 500.0; float step = 1.0;
> = 60.0;

uniform float blur_radius<
    string label = "Desenfoque (px)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 40.0; float step = 0.5;
> = 10.0;

uniform float refraction<
    string label = "Refraccion (px, negativo = lupa)";
    string widget_type = "slider";
    float minimum = -150.0; float maximum = 150.0; float step = 1.0;
> = 45.0;

uniform float bezel<
    string label = "Ancho del bisel (px)";
    string widget_type = "slider";
    float minimum = 1.0; float maximum = 250.0; float step = 1.0;
> = 40.0;

uniform float dispersion<
    string label = "Dispersion de color";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 0.25;

uniform float saturation<
    string label = "Saturacion";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 2.0; float step = 0.01;
> = 1.3;

uniform float4 tint_color = {1.0, 1.0, 1.0, 1.0};

uniform float tint_amount<
    string label = "Cantidad de tinte";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 0.12;

uniform float highlight<
    string label = "Brillo de borde";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 2.0; float step = 0.01;
> = 0.8;

uniform float light_angle<
    string label = "Angulo de la luz (grados)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 360.0; float step = 1.0;
> = 135.0;

uniform float light_speed<
    string label = "Giro de la luz (grados/s)";
    string widget_type = "slider";
    float minimum = -180.0; float maximum = 180.0; float step = 1.0;
> = 0.0;

uniform float shadow_opacity<
    string label = "Opacidad de sombra";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 0.35;

uniform float shadow_size<
    string label = "Tamano de sombra (px)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 200.0; float step = 1.0;
> = 40.0;

uniform float liquid_wave<
    string label = "Ondulacion liquida (px)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 30.0; float step = 0.5;
> = 0.0;

uniform float liquid_speed<
    string label = "Velocidad de ondulacion";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 10.0; float step = 0.1;
> = 1.5;

uniform float frost_amount<
    string label = "Grano de escarcha (Frost)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 0.0;

// Hash rápido sin texturas para rotación de muestras y efecto escarcha.
// Por qué no el clásico frac(sin(dot(p, ...)) * 43758.5453): con coordenadas en píxeles el
// argumento de sin() llega a ~150,000 y en varias GPUs (Intel, algunas AMD, OpenGL en general)
// sin() pierde precisión a esa escala; el "ruido" sale con patrones o franjas visibles.
// Este hash (Dave Hoskins, "Hash without Sine") solo usa frac/multiplicaciones, así que
// se ve igual en cualquier GPU y backend (D3D11 u OpenGL).
float hash12(float2 p)
{
    float3 p3 = frac(float3(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

// Distancia con signo a un rectángulo redondeado (negativa adentro)
float sdRoundBox(float2 p, float2 b, float r)
{
    float2 q = abs(p) - b + float2(r, r);
    return length(max(q, float2(0.0, 0.0))) + min(max(q.x, q.y), 0.0) - r;
}

// Desenfoque en disco con 16 muestras en espiral (ángulo áureo)
float3 sampleBlur(float2 uv, float radius_px, float rot_offset)
{
    if (radius_px < 0.5)
        return image.Sample(textureSampler, uv).rgb;

    float3 acc = float3(0.0, 0.0, 0.0);
    float fi = 0.0;
    for (int i = 0; i < 16; i++) {
        float a = fi * 2.39996323 + rot_offset;
        float rr = sqrt((fi + 0.5) / 16.0) * radius_px;
        float2 o = float2(cos(a), sin(a)) * rr * uv_pixel_interval;
        acc += image.Sample(textureSampler, uv + o).rgb;
        fi += 1.0;
    }
    return acc / 16.0;
}

float4 mainImage(VertData v_in) : TARGET
{
    float2 uv = v_in.uv;
    float4 base = image.Sample(textureSampler, uv);

    float2 pos = uv * uv_size;
    float2 center = float2(panel_x, panel_y) * 0.01 * uv_size;
    float2 half_size = float2(panel_w, panel_h) * 0.005 * uv_size;
    float r = min(corner_radius, min(half_size.x, half_size.y));
    float2 p = pos - center;
    float d = sdRoundBox(p, half_size, r);

    // Fuera del panel: sombra suave desplazada hacia abajo
    float ds = sdRoundBox(p - float2(0.0, shadow_size * 0.35), half_size, r);
    float sh = (1.0 - smoothstep(0.0, max(shadow_size, 0.001), ds)) * shadow_opacity;
    float3 outside = base.rgb * (1.0 - sh);

    if (d > 1.0)
        return float4(outside, base.a);

    // Normal analítica suave del bisel (evita 4 llamadas extra a sdRoundBox y pliegues a 45°)
    float r_bezel = min(max(r, bezel), min(half_size.x, half_size.y));
    float2 q_n = abs(p) - half_size + float2(r_bezel, r_bezel);
    float2 n_corner = max(q_n, float2(0.0, 0.0));
    float2 n_inside = (q_n.x > q_n.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
    float2 n_dir = (length(n_corner) > 0.0001) ? n_corner : n_inside;
    float2 sgn = float2(p.x >= 0.0 ? 1.0 : -1.0, p.y >= 0.0 ? 1.0 : -1.0);
    float2 n = (n_dir * sgn) / max(length(n_dir), 0.0001);

    // 1 justo en el borde, 0 en la zona plana del centro
    float edge = 1.0 - saturate(-d / max(bezel, 1.0));
    float lens = edge * edge;

    // Ondulación líquida opcional en el vidrio y la normal
    float2 wave_offset_px = float2(0.0, 0.0);
    if (liquid_wave > 0.001) {
        float t = elapsed_time * liquid_speed;
        float2 wp = p * 0.035;
        float2 w = float2(
            sin(wp.x + t) * cos(wp.y * 0.8 - t * 0.7),
            cos(wp.y + t * 0.9) * sin(wp.x * 0.8 + t * 0.6)
        );
        wave_offset_px = w * liquid_wave * (0.35 + 0.65 * edge);
        float2 nw = n + w * saturate(liquid_wave * 0.015);
        n = nw / max(length(nw), 0.0001);
    }

    // Refracción: el bisel muestra el contenido desplazado, como un borde de vidrio convexo
    float2 disp_px = n * (refraction * lens) + wave_offset_px;
    float2 disp = disp_px * uv_pixel_interval;

    // Ruido por píxel para escarcha (rota el disco de desenfoque y añade grano sutil)
    // Se usa p (relativo al centro del panel) y no pos (absoluto en pantalla) para que el grano
    // quede "pegado" al vidrio: si el panel se anima (Move Transition, etc.), la escarcha se mueve
    // con él en vez de verse como una textura fija sobre la que el panel se desliza.
    float noise = hash12(p);
    float rot = (frost_amount > 0.001) ? (noise * 6.2831853 * saturate(frost_amount * 2.0)) : 0.0;

    // Optimización: 1 sola pasada de blur si no hay dispersión perceptible en este píxel
    float3 col;
    if (dispersion < 0.001 || length(disp_px) * dispersion < 0.15) {
        col = sampleBlur(uv + disp, blur_radius, rot);
    } else {
        col.r = sampleBlur(uv + disp * (1.0 + dispersion), blur_radius, rot).r;
        col.g = sampleBlur(uv + disp, blur_radius, rot).g;
        col.b = sampleBlur(uv + disp * (1.0 - dispersion), blur_radius, rot).b;
    }

    // Saturación, tinte y grano de escarcha
    float lum = dot(col, float3(0.2126, 0.7152, 0.0722));
    col = lerp(float3(lum, lum, lum), col, saturation);
    col = lerp(col, tint_color.rgb, tint_amount);
    if (frost_amount > 0.001)
        col += (noise - 0.5) * frost_amount * 0.12;

    // Brillo especular en el borde según la dirección de la luz
    float ang = radians(light_angle + light_speed * elapsed_time);
    float2 L = float2(cos(ang), -sin(ang));
    float facing = max(dot(n, L), 0.0) + 0.4 * max(dot(n, -L), 0.0);
    float rim = pow(edge, 4.0) * facing;
    float edge_line = 1.0 - smoothstep(0.0, 1.5, -d);   // filo fino de 1-2 px
    col += highlight * (rim * 0.45 + edge_line * 0.25 * (0.4 + facing));

    // Borde antialias
    float aa = saturate(0.5 - d);
    return float4(lerp(outside, saturate(col), aa), base.a);
}

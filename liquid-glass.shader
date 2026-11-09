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

// Distancia con signo a un rectángulo redondeado (negativa adentro)
float sdRoundBox(float2 p, float2 b, float r)
{
    float2 q = abs(p) - b + float2(r, r);
    return length(max(q, float2(0.0, 0.0))) + min(max(q.x, q.y), 0.0) - r;
}

// Desenfoque en disco con 16 muestras en espiral (ángulo áureo)
float3 sampleBlur(float2 uv, float radius_px)
{
    if (radius_px < 0.5)
        return image.Sample(textureSampler, uv).rgb;

    float3 acc = float3(0.0, 0.0, 0.0);
    float fi = 0.0;
    for (int i = 0; i < 16; i++) {
        float a = fi * 2.39996323;
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

    // Normal del borde a partir del gradiente de la distancia
    float2 ex = float2(1.0, 0.0);
    float2 ey = float2(0.0, 1.0);
    float2 n = float2(sdRoundBox(p + ex, half_size, r) - sdRoundBox(p - ex, half_size, r),
                      sdRoundBox(p + ey, half_size, r) - sdRoundBox(p - ey, half_size, r));
    n = n / max(length(n), 0.0001);

    // 1 justo en el borde, 0 en la zona plana del centro
    float edge = 1.0 - saturate(-d / max(bezel, 1.0));
    float lens = edge * edge;

    // Refracción: el bisel muestra el contenido desplazado, como un borde de vidrio convexo
    float2 disp = n * refraction * lens * uv_pixel_interval;

    float3 col;
    col.r = sampleBlur(uv + disp * (1.0 + dispersion), blur_radius).r;
    col.g = sampleBlur(uv + disp, blur_radius).g;
    col.b = sampleBlur(uv + disp * (1.0 - dispersion), blur_radius).b;

    // Saturación y tinte
    float lum = dot(col, float3(0.2126, 0.7152, 0.0722));
    col = lerp(float3(lum, lum, lum), col, saturation);
    col = lerp(col, tint_color.rgb, tint_amount);

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

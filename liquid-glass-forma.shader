// Liquid Glass con forma definida por otra fuente (OBS Studio + obs-shaderfilter)
//
// Uso:
//   1. Crea una escena aparte, por ejemplo "Forma Vidrio", con las figuras donde quieres el vidrio
//      (PNG con transparencia, texto, color sólido recortado, etc.). Esa escena no tiene que salir en vivo.
//   2. En la escena principal agrega el filtro "User-defined shader" con este archivo.
//   3. En "Fuente de forma" elige la escena "Forma Vidrio".
// Donde la forma es opaca (o blanca, en modo brillo) aparece vidrio que refracta la escena principal.

uniform texture2d shape_source<
    string label = "Fuente de forma";
>;

uniform bool use_luminance<
    string label = "Usar brillo en vez de transparencia (blanco = vidrio)";
> = false;

uniform float blur_radius<
    string label = "Desenfoque (px)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 40.0; float step = 0.5;
> = 10.0;

uniform float bezel<
    string label = "Ancho del bisel (px)";
    string widget_type = "slider";
    float minimum = 1.0; float maximum = 120.0; float step = 1.0;
> = 30.0;

uniform float refraction<
    string label = "Refraccion (px, negativo = lupa)";
    string widget_type = "slider";
    float minimum = -150.0; float maximum = 150.0; float step = 1.0;
> = 45.0;

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
    float minimum = 1.0; float maximum = 120.0; float step = 1.0;
> = 30.0;

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

// 0 = perfil suave (edge², el original); 1 = perfil convexo circular tipo iOS.
// El circular concentra casi todo el desplazamiento en los últimos píxeles de la orilla, así el
// fondo se "comprime y envuelve" junto al borde y el vidrio se ve grueso en vez de plano.
uniform float bezel_profile<
    string label = "Perfil del bisel (0 suave, 1 convexo iOS)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 0.0;

// Cuánto se desvanece el tinte hacia la orilla (0 = tinte parejo; 1 = sin tinte en el borde).
// Por qué: en iOS un vidrio muy oscuro (barra de búsqueda, Siri) sigue viéndose como vidrio
// porque el bisel deja ver el fondo brillante y refractado aunque el centro sea casi negro.
// Con tinte parejo, un tinte negro fuerte convierte la pieza en una mancha negra plana.
uniform float tint_edge<
    string label = "Tinte en el bisel (1 = se desvanece)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 0.0;

// Cuánto brillo recibe el lado del borde opuesto a la luz. Antes era un 0.4 fijo, lo que
// iluminaba todo el contorno; en iOS el reflejo está casi solo del lado de la luz (usa ~0).
uniform float back_light<
    string label = "Luz del lado opuesto";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 0.4;

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

// Cobertura de la forma en un punto: 0 = sin vidrio, 1 = vidrio
float shapeAt(float2 uv)
{
    float4 s = shape_source.Sample(textureSampler, uv);
    if (use_luminance)
        return saturate(dot(s.rgb, float3(0.2126, 0.7152, 0.0722)));
    return s.a;
}

// Forma desenfocada para proyectar la sombra exterior
float heightAt(float2 uv, float radius_px)
{
    float acc = shapeAt(uv);
    float fi = 0.0;
    for (int i = 0; i < 16; i++) {
        float a = fi * 2.39996323;
        float rr = sqrt((fi + 0.5) / 16.0) * radius_px;
        acc += shapeAt(uv + float2(cos(a), sin(a)) * rr * uv_pixel_interval);
        fi += 1.0;
    }
    return acc / 17.0;
}

// Calcula en una sola pasada la normal exterior (xy) y la altura suave (z) del bisel.
// Usa 32 muestras con peso cónico radial para eliminar el escalonamiento (stepping)
// que producían las diferencias finitas sobre bordes duros.
float3 bevelAt(float2 uv, float radius_px)
{
    float w_sum = 1.0;
    float h_acc = shapeAt(uv);
    float2 g_acc = float2(0.0, 0.0);
    float fi = 0.0;
    for (int i = 0; i < 32; i++) {
        float a = fi * 2.39996323;
        float t = sqrt((fi + 0.5) / 32.0);
        float2 dir = float2(cos(a), sin(a));
        float s = shapeAt(uv + dir * (t * radius_px) * uv_pixel_interval);
        float w = 1.0 - t * 0.75;
        h_acc += s * w;
        w_sum += w;
        g_acc += dir * ((1.0 - s) * w);
        fi += 1.0;
    }
    float h = h_acc / w_sum;
    float2 n = g_acc / max(length(g_acc), 0.0001);
    return float3(n.x, n.y, h);
}

// Desenfoque de la escena principal: 32 muestras en espiral con peso gaussiano.
// Por qué 32 y no 16: con radios grandes, 16 muestras quedan tan separadas que en vez de un
// blur se ven "copias" nítidas superpuestas (bloques y rayas). El peso gaussiano hace que el
// anillo exterior, que es el que más delata las copias, aporte poco, como un blur real.
float3 sceneBlur(float2 uv, float radius_px, float rot_offset)
{
    if (radius_px < 0.5)
        return image.Sample(textureSampler, uv).rgb;

    float3 acc = float3(0.0, 0.0, 0.0);
    float w_sum = 0.0;
    float fi = 0.0;
    for (int i = 0; i < 32; i++) {
        float a = fi * 2.39996323 + rot_offset;
        float t = sqrt((fi + 0.5) / 32.0);          // 0..1, reparto uniforme en el disco
        float w = exp(-2.5 * t * t);                // gaussiana: el borde del disco pesa ~8%
        acc += image.Sample(textureSampler, uv + float2(cos(a), sin(a)) * (t * radius_px) * uv_pixel_interval).rgb * w;
        w_sum += w;
        fi += 1.0;
    }
    return acc / w_sum;
}

float4 mainImage(VertData v_in) : TARGET
{
    float2 uv = v_in.uv;
    float4 base = image.Sample(textureSampler, uv);
    float cover = shapeAt(uv);

    // Sombra: solo se evalúa cuando el píxel no está 100% cubierto por el vidrio
    float3 outside = base.rgb;
    if (cover < 0.999 && shadow_opacity > 0.001) {
        float shadow_h = heightAt(uv - float2(0.0, shadow_size * 0.35) * uv_pixel_interval, shadow_size);
        outside = base.rgb * (1.0 - shadow_h * shadow_opacity * (1.0 - cover));
    }

    if (cover <= 0.001)
        return float4(outside, base.a);

    // Altura y normal suave del vidrio en una sola pasada (33 lecturas en vez de 85)
    float3 b = bevelAt(uv, max(bezel, 1.0));
    float2 n = b.xy;
    float h = b.z;

    float edge = saturate((1.0 - h) * 2.0);   // 1 en el borde, 0 en la zona plana
    // Perfil circular: 1 - sqrt(1 - edge²) es la "altura" de un cuarto de círculo; su pendiente
    // se dispara en la orilla, que es donde iOS comprime el fondo.
    float lens_circ = 1.0 - sqrt(saturate(1.0 - edge * edge));
    float lens = lerp(edge * edge, lens_circ, bezel_profile);

    // Ondulación líquida opcional en el vidrio y la normal
    float2 pos = uv * uv_size;
    float2 wave_offset_px = float2(0.0, 0.0);
    if (liquid_wave > 0.001) {
        float t = elapsed_time * liquid_speed;
        float2 wp = pos * 0.035;
        float2 w = float2(
            sin(wp.x + t) * cos(wp.y * 0.8 - t * 0.7),
            cos(wp.y + t * 0.9) * sin(wp.x * 0.8 + t * 0.6)
        );
        wave_offset_px = w * liquid_wave * (0.35 + 0.65 * edge);
        // Ojo: en la zona plana del centro bevelAt devuelve n = (0,0), así que aquí nw = w * k y al
        // normalizar queda un vector unitario con dirección arbitraria. Es inofensivo porque ahí
        // edge = 0, y lens, rim y edge_glint (lo único que usa n) valen 0. Si en el futuro usas n
        // fuera del bisel, multiplica primero por edge o revisa length(b.xy) antes de normalizar.
        float2 nw = n + w * saturate(liquid_wave * 0.015);
        n = nw / max(length(nw), 0.0001);
    }

    // Refracción en el bisel con dispersión de color
    float2 disp_px = n * (refraction * lens) + wave_offset_px;
    float2 disp = disp_px * uv_pixel_interval;

    // Ruido por píxel para escarcha (rota el disco de desenfoque y añade grano sutil)
    // Aquí el grano usa pos (absoluto en pantalla) a propósito: la forma viene de otra fuente y el
    // shader no sabe dónde está ni cómo se mueve, así que no hay un origen local al cual anclarlo.
    // Consecuencia: si animas la fuente de forma, el vidrio se desliza sobre una escarcha fija.
    float noise = hash12(pos);
    float rot = (frost_amount > 0.001) ? (noise * 6.2831853 * saturate(frost_amount * 2.0)) : 0.0;

    // Optimización: 1 sola pasada de blur si no hay dispersión perceptible en este píxel
    float3 col;
    if (dispersion < 0.001 || length(disp_px) * dispersion < 0.15) {
        col = sceneBlur(uv + disp, blur_radius, rot);
    } else {
        col.r = sceneBlur(uv + disp * (1.0 + dispersion), blur_radius, rot).r;
        col.g = sceneBlur(uv + disp, blur_radius, rot).g;
        col.b = sceneBlur(uv + disp * (1.0 - dispersion), blur_radius, rot).b;
    }

    // Saturación, tinte y grano de escarcha
    float lum = dot(col, float3(0.2126, 0.7152, 0.0722));
    col = lerp(float3(lum, lum, lum), col, saturation);
    // edge vale 1 en la orilla y 0 en la zona plana: el tinte se reduce solo dentro del bisel
    col = lerp(col, tint_color.rgb, tint_amount * (1.0 - tint_edge * edge));
    if (frost_amount > 0.001)
        col += (noise - 0.5) * frost_amount * 0.12;

    // Brillo especular según la dirección de la luz
    float ang = radians(light_angle + light_speed * elapsed_time);
    float2 L = float2(cos(ang), -sin(ang));
    // back_light reemplaza al 0.4 fijo: con 0 el reflejo queda solo del lado de la luz
    float facing = max(dot(n, L), 0.0) + back_light * max(dot(n, -L), 0.0);
    float rim = pow(edge, 4.0) * facing;
    float edge_glint = smoothstep(0.85, 1.0, edge);
    col += highlight * (rim * 0.45 + edge_glint * 0.2 * (back_light + facing));

    return float4(lerp(outside, saturate(col), cover), base.a);
}

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

// Cobertura de la forma en un punto: 0 = sin vidrio, 1 = vidrio
float shapeAt(float2 uv)
{
    float4 s = shape_source.Sample(textureSampler, uv);
    if (use_luminance)
        return saturate(dot(s.rgb, float3(0.2126, 0.7152, 0.0722)));
    return s.a;
}

// Forma desenfocada: funciona como "altura" del vidrio (0.5 justo en el borde, 1 adentro)
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

// Desenfoque de la escena principal
float3 sceneBlur(float2 uv, float radius_px)
{
    if (radius_px < 0.5)
        return image.Sample(textureSampler, uv).rgb;

    float3 acc = float3(0.0, 0.0, 0.0);
    float fi = 0.0;
    for (int i = 0; i < 16; i++) {
        float a = fi * 2.39996323;
        float rr = sqrt((fi + 0.5) / 16.0) * radius_px;
        acc += image.Sample(textureSampler, uv + float2(cos(a), sin(a)) * rr * uv_pixel_interval).rgb;
        fi += 1.0;
    }
    return acc / 16.0;
}

float4 mainImage(VertData v_in) : TARGET
{
    float2 uv = v_in.uv;
    float4 base = image.Sample(textureSampler, uv);
    float cover = shapeAt(uv);

    // Sombra: forma desenfocada y desplazada hacia abajo
    float shadow_h = heightAt(uv - float2(0.0, shadow_size * 0.35) * uv_pixel_interval, shadow_size);
    float3 outside = base.rgb * (1.0 - shadow_h * shadow_opacity * (1.0 - cover));

    if (cover <= 0.001)
        return float4(outside, base.a);

    // Altura y normal del vidrio a partir de la forma desenfocada
    float h = heightAt(uv, bezel);
    float dx = 2.0 * uv_pixel_interval.x;
    float dy = 2.0 * uv_pixel_interval.y;
    float2 grad = float2(heightAt(uv + float2(dx, 0.0), bezel) - heightAt(uv - float2(dx, 0.0), bezel),
                         heightAt(uv + float2(0.0, dy), bezel) - heightAt(uv - float2(0.0, dy), bezel));
    float2 n = -grad / max(length(grad), 0.0001);   // apunta hacia afuera de la forma

    float edge = saturate((1.0 - h) * 2.0);   // 1 en el borde, 0 en la zona plana
    float lens = edge * edge;

    // Refracción en el bisel con dispersión de color
    float2 disp = n * refraction * lens * uv_pixel_interval;
    float3 col;
    col.r = sceneBlur(uv + disp * (1.0 + dispersion), blur_radius).r;
    col.g = sceneBlur(uv + disp, blur_radius).g;
    col.b = sceneBlur(uv + disp * (1.0 - dispersion), blur_radius).b;

    // Saturación y tinte
    float lum = dot(col, float3(0.2126, 0.7152, 0.0722));
    col = lerp(float3(lum, lum, lum), col, saturation);
    col = lerp(col, tint_color.rgb, tint_amount);

    // Brillo especular según la dirección de la luz
    float ang = radians(light_angle + light_speed * elapsed_time);
    float2 L = float2(cos(ang), -sin(ang));
    float facing = max(dot(n, L), 0.0) + 0.4 * max(dot(n, -L), 0.0);
    float rim = pow(edge, 4.0) * facing;
    float edge_glint = smoothstep(0.85, 1.0, edge);
    col += highlight * (rim * 0.45 + edge_glint * 0.2 * (0.4 + facing));

    return float4(lerp(outside, saturate(col), cover), base.a);
}

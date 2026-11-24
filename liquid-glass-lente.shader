// Vidrio para OBS con obs-shaderfilter, modo "User-defined shader".
// La curvatura del bisel define la normal que desvía el rayo hacia la imagen.

uniform float lens_x<
    string label = "Centro X (%)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 100.0; float step = 0.1;
> = 50.0;

uniform float lens_y<
    string label = "Centro Y (%)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 100.0; float step = 0.1;
> = 50.0;

uniform float lens_width<
    string label = "Ancho (%)";
    string widget_type = "slider";
    float minimum = 1.0; float maximum = 100.0; float step = 0.1;
> = 44.0;

uniform float lens_height<
    string label = "Alto (%)";
    string widget_type = "slider";
    float minimum = 1.0; float maximum = 100.0; float step = 0.1;
> = 29.0;

uniform float lens_radius<
    string label = "Radio de esquinas (px)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 500.0; float step = 1.0;
> = 52.0;

uniform float lens_bevel<
    string label = "Ancho del bisel (px)";
    string widget_type = "slider";
    float minimum = 1.0; float maximum = 160.0; float step = 1.0;
> = 32.0;

uniform float lens_depth<
    string label = "Grosor del vidrio (px)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 200.0; float step = 1.0;
> = 48.0;

uniform float lens_blur<
    string label = "Desenfoque (px)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 24.0; float step = 0.5;
> = 6.5;

uniform float lens_dispersion<
    string label = "Dispersion de color";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 0.24;

uniform float4 lens_tint = {0.72, 0.86, 1.0, 1.0};

uniform float lens_tint_amount<
    string label = "Cantidad de tinte";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 0.12;

uniform float lens_light_angle<
    string label = "Angulo de la luz (grados)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 360.0; float step = 1.0;
> = 135.0;

uniform float lens_highlight<
    string label = "Intensidad del reflejo";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 2.0; float step = 0.01;
> = 1.0;

uniform float lens_ripple<
    string label = "Ondulacion animada";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 0.0;

uniform float lens_shadow_size<
    string label = "Tamano de sombra (px)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 120.0; float step = 1.0;
> = 24.0;

uniform float lens_shadow_opacity<
    string label = "Opacidad de sombra";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 0.24;

float lensDistance(float2 position, float2 half_size, float radius)
{
    float2 q = abs(position) - half_size + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

float2 lensOutward(float2 position, float2 half_size, float radius)
{
    float2 q = abs(position) - half_size + radius;
    float2 corner = max(q, 0.0);
    float corner_length = length(corner);
    if (corner_length > 0.0001)
        return sign(position) * corner / corner_length;

    float2 side = q.x > q.y ? float2(1.0, 0.0) : float2(0.0, 1.0);
    return sign(position) * side;
}

// Pendiente del canto (tan de la inclinación) según la posición en el bisel: 0 al inicio, 1 en la orilla.
// El seno se limita a 0.94 (unos 70°) para que la normal nunca quede horizontal.
float lensSlope(float edge)
{
    float tilt_sine = 0.94 * pow(edge, 1.6);
    return tilt_sine / sqrt(1.0 - tilt_sine * tilt_sine);
}

// Sagita: cuánto ha bajado la superficie desde que empieza el bisel. Es la integral de la pendiente
// sobre la distancia recorrida (edge * ancho del bisel). La pendiente no tiene integral cerrada, así
// que se suma con 8 pasos de punto medio: solo aritmética, sin lecturas de textura. El error es
// < 1% en casi todo el bisel y ~3% (medio píxel) en la orilla misma, donde la curva es más empinada.
float lensSag(float edge, float bevel_width)
{
    float step_size = edge / 8.0;
    float total = 0.0;
    for (int i = 0; i < 8; i++)
        total += lensSlope((float(i) + 0.5) * step_size);
    return total * step_size * bevel_width;
}

// El rayo entra por la superficie, se refracta y viaja hasta el fondo. thickness es el grosor del
// vidrio en ese punto: en la parte plana es lens_depth; en el canto, lens_depth menos la sagita.
float2 lensRayOffset(float3 surface_normal, float index_of_refraction, float thickness)
{
    float3 ray = refract(float3(0.0, 0.0, -1.0), surface_normal, 1.0 / index_of_refraction);
    return thickness * ray.xy / max(-ray.z, 0.001);
}

// Desenfoque con 24 muestras en espiral áurea (ángulo de oro 137.5°) y peso gaussiano.
// rot y t_off cambian en cada píxel (ruido IGN): así las muestras no caen siempre en los mismos
// puntos y en lugar de copias nítidas de una orilla aparece un grano finísimo que no se nota.
// SampleLevel en vez de Sample: dentro de un bucle o de un if, Sample necesita derivadas que la GPU
// no garantiza (avisos X3570 y comportamiento indefinido en GLSL, Mac y Linux).
//
// Alfa: obs-shaderfilter entrega `image` con alfa directo (no premultiplicado): antes de llamar al
// shader lo divide entre alfa con la técnica DrawAlphaDivide. En un píxel transparente el color no
// significa nada, así que cada muestra se pesa por su alfa (rgb * a). El resultado sale premultiplicado:
// rgb = suma(color * a * w), a = suma(a * w). Quien lo usa divide rgb entre a para volver al color real.
float4 lensSample(float2 uv, float radius_px, float rot, float t_off)
{
    if (radius_px < 0.5) {
        float4 s = image.SampleLevel(textureSampler, uv, 0.0);
        return float4(s.rgb * s.a, s.a);
    }

    float4 color = float4(0.0, 0.0, 0.0, 0.0);
    float weight_sum = 0.0;
    float fi = 0.0;
    for (int tap = 0; tap < 24; tap++) {
        float a = fi * 2.39996323 + rot;
        float t = sqrt((fi + t_off) / 24.0);        // 0..1, reparto uniforme en el disco
        float w = exp(-2.5 * t * t);                // el borde del disco pesa ~8%
        float2 o = float2(cos(a), sin(a)) * (t * radius_px) * uv_pixel_interval;
        float4 s = image.SampleLevel(textureSampler, uv + o, 0.0);
        color += float4(s.rgb * s.a, s.a) * w;
        weight_sum += w;
        fi += 1.0;
    }
    return color / weight_sum;
}

float4 mainImage(VertData v_in) : TARGET
{
    float2 uv = v_in.uv;
    float4 source = image.Sample(textureSampler, uv);
    if (source.a <= 0.0)
        return source;

    float2 position = (uv - float2(lens_x, lens_y) * 0.01) * uv_size;
    float2 half_size = float2(lens_width, lens_height) * 0.005 * uv_size;
    float min_half_size = min(half_size.x, half_size.y);
    float radius = min(lens_radius, min_half_size);
    float shape_distance = lensDistance(position, half_size, radius);
    float coverage = saturate(0.5 - shape_distance);

    float3 background = source.rgb;
    if (lens_shadow_size > 0.0 && lens_shadow_opacity > 0.0 && shape_distance < lens_shadow_size * 1.35) {
        float2 shadow_offset = float2(0.0, 0.35 * lens_shadow_size);
        float shadow_distance = lensDistance(position - shadow_offset, half_size, radius);
        float shadow = 1.0 - smoothstep(0.0, lens_shadow_size, shadow_distance);
        background *= 1.0 - lens_shadow_opacity * shadow;
    }
    if (coverage <= 0.0)
        return float4(background, source.a);

    float bevel_width = min(lens_bevel, max(0.5, 0.75 * min_half_size));
    // La dirección del canto se calcula con un radio de al menos el ancho del bisel. Con el radio de
    // las esquinas, si el bisel es más ancho, la zona curva llega a la diagonal de la esquina, donde
    // la dirección salta de golpe de "hacia arriba" a "hacia un lado" y aparece un pliegue con picos.
    float direction_radius = min(max(radius, bevel_width), min_half_size);
    float2 outward = lensOutward(position, half_size, direction_radius);
    float edge = saturate(1.0 + shape_distance / bevel_width);
    float2 slope = outward * lensSlope(edge);
    if (lens_ripple > 0.0) {
        float2 wave_position = position / max(min(uv_size.x, uv_size.y), 1.0);
        float time = elapsed_time * 1.65;
        slope += (0.10 * lens_ripple) * float2(
            sin(dot(wave_position, float2(37.0, 14.0)) + time),
            sin(dot(wave_position, float2(-11.0, 43.0)) - time * 0.84)
        );
    }
    float3 surface_normal = normalize(float3(slope, 1.0));

    // La ley de Snell da un desplazamiento distinto para cada longitud de onda.
    float index_of_refraction = 1.49;
    // El fondo está a lens_depth bajo la cara de arriba de la parte plana. En el canto la superficie
    // ya bajó la sagita, así que el rayo recorre menos vidrio. Con grosor constante el desplazamiento
    // crecía hasta la orilla y la imagen se doblaba en espejo en una franja más ancha de lo real.
    float thickness = max(lens_depth - lensSag(edge, bevel_width), 0.0);
    float2 bend = lensRayOffset(surface_normal, index_of_refraction, thickness);
    float blur = lens_blur * lerp(1.0, 0.35, edge);

    // Ruido IGN (Jimenez 2014): un valor distinto por píxel, estable entre cuadros.
    float ign = frac(52.9829189 * frac(dot(floor(uv * uv_size), float2(0.06711056, 0.00583715))));
    float rot = ign * 6.2831853;
    float t_off = frac(ign * 7.0);

    float4 glass = lensSample(uv + bend * uv_pixel_interval, blur, rot, t_off);
    float3 sampled_alpha = glass.aaa;
    if (lens_dispersion > 0.0 && dot(bend, bend) > 0.25) {
        float spread = 0.12 * lens_dispersion;
        float2 red_uv = uv + lensRayOffset(surface_normal, index_of_refraction - spread, thickness) * uv_pixel_interval;
        float2 blue_uv = uv + lensRayOffset(surface_normal, index_of_refraction + spread, thickness) * uv_pixel_interval;
        float4 red = lensSample(red_uv, blur, rot, t_off);
        float4 blue = lensSample(blue_uv, blur, rot, t_off);
        glass.r = red.r;
        glass.b = blue.b;
        sampled_alpha.r = red.a;
        sampled_alpha.b = blue.a;
    }

    // Volver de premultiplicado a color real. Donde la muestra refractada cayó en una zona más
    // transparente que este píxel, se completa con el color local. La salida conserva el alfa de la
    // fuente y va en alfa directo, que es lo que obs-shaderfilter espera por defecto.
    float3 seen = glass.rgb / max(sampled_alpha, 0.0001);
    float3 filled = saturate(sampled_alpha / max(source.a, 0.0001));
    float3 glass_color = lerp(source.rgb, seen, filled);

    // Absorción (ley de Beer-Lambert): la luz que cruza el vidrio se atenúa como exp(-k * camino).
    // El tinte es el color que se ve a través de la parte plana (camino = lens_depth); de ahí sale k
    // para cada canal. En el canto el camino cambia (menos grosor, rayo más inclinado) y el tinte
    // cambia solo, sin un factor inventado. Filtrar multiplica: nunca aclara un fondo oscuro.
    float3 ray = refract(float3(0.0, 0.0, -1.0), surface_normal, 1.0 / index_of_refraction);
    float path = thickness / max(-ray.z, 0.001);
    float3 tint_through_flat = lerp(float3(1.0, 1.0, 1.0), lens_tint.rgb, lens_tint_amount * lens_tint.a);
    float3 absorption = -log(max(tint_through_flat, 0.001)) / max(lens_depth, 1.0);
    glass_color *= exp(-absorption * path);

    float angle = radians(lens_light_angle);
    float2 light_direction = float2(cos(angle), -sin(angle));
    float3 light_color = float3(0.91, 0.96, 1.0);
    float3 halfway = normalize(float3(light_direction, 1.35));
    float specular = pow(saturate(dot(surface_normal, halfway)), 28.0) * smoothstep(0.0, 0.35, edge);
    float grazing = pow(1.0 - saturate(surface_normal.z), 5.0);
    float fresnel = 0.04 + 0.96 * grazing;
    float rim = (1.0 - smoothstep(0.15, 1.55, abs(shape_distance)))
        * (0.45 + 0.55 * saturate(dot(outward, light_direction)));

    // Reflejo del entorno. Fresnel dice cuánto se refleja; lo reflejado no es un cielo blanco sino lo
    // que rodea al vidrio, y lo único que hay alrededor es la propia escena. Se lee la escena desenfocada
    // en la dirección del rayo reflejado (como los reflejos en espacio de pantalla de los videojuegos):
    // sobre fondo oscuro el canto refleja oscuro, sobre fondo claro refleja claro.
    if (edge > 0.0) {
        float3 reflected = reflect(float3(0.0, 0.0, -1.0), surface_normal);
        float2 env_offset = reflected.xy / max(reflected.z, 0.25) * (lens_depth + bevel_width);
        float4 env = lensSample(uv + env_offset * uv_pixel_interval, lens_blur * 2.0 + 8.0, rot, t_off);
        float3 env_color = env.a > 0.0001 ? env.rgb / env.a : glass_color;
        glass_color = lerp(glass_color, env_color, saturate(fresnel * lens_highlight));
    }

    // La luz (especular y filo) sí es una fuente brillante: se suma en vez de mezclar.
    glass_color += light_color * (lens_highlight * (0.68 * specular + 0.22 * rim));
    glass_color = saturate(glass_color);
    return float4(lerp(background, glass_color, coverage), source.a);
}

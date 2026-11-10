// Liquid Glass for OBS Studio (obs-shaderfilter plugin, "User-defined shader" mode)
// Draws a glass panel with blur, bezel refraction, color dispersion, tint, rim highlight
// and drop shadow over the image of the source or scene it is applied to.
// For several panels, add the filter several times.

uniform float panel_x<
    string label = "Center X (%)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 100.0; float step = 0.1;
> = 50.0;

uniform float panel_y<
    string label = "Center Y (%)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 100.0; float step = 0.1;
> = 50.0;

uniform float panel_w<
    string label = "Width (%)";
    string widget_type = "slider";
    float minimum = 1.0; float maximum = 100.0; float step = 0.1;
> = 40.0;

uniform float panel_h<
    string label = "Height (%)";
    string widget_type = "slider";
    float minimum = 1.0; float maximum = 100.0; float step = 0.1;
> = 25.0;

uniform float corner_radius<
    string label = "Corner radius (px)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 500.0; float step = 1.0;
> = 60.0;

uniform float blur_radius<
    string label = "Blur (px)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 40.0; float step = 0.5;
> = 10.0;

uniform float refraction<
    string label = "Refraction (px, negative = magnifier)";
    string widget_type = "slider";
    float minimum = -150.0; float maximum = 150.0; float step = 1.0;
> = 45.0;

uniform float bezel<
    string label = "Bezel width (px)";
    string widget_type = "slider";
    float minimum = 1.0; float maximum = 250.0; float step = 1.0;
> = 40.0;

uniform float dispersion<
    string label = "Color dispersion";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 0.25;

uniform float saturation<
    string label = "Saturation";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 2.0; float step = 0.01;
> = 1.3;

uniform float4 tint_color = {1.0, 1.0, 1.0, 1.0};

uniform float tint_amount<
    string label = "Tint amount";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 0.12;

uniform float highlight<
    string label = "Rim highlight";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 2.0; float step = 0.01;
> = 0.8;

uniform float light_angle<
    string label = "Light angle (degrees)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 360.0; float step = 1.0;
> = 135.0;

uniform float light_speed<
    string label = "Light rotation (degrees/s)";
    string widget_type = "slider";
    float minimum = -180.0; float maximum = 180.0; float step = 1.0;
> = 0.0;

uniform float shadow_opacity<
    string label = "Shadow opacity";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 0.35;

uniform float shadow_size<
    string label = "Shadow size (px)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 200.0; float step = 1.0;
> = 40.0;

uniform float liquid_wave<
    string label = "Liquid wave (px)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 30.0; float step = 0.5;
> = 0.0;

uniform float liquid_speed<
    string label = "Wave speed";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 10.0; float step = 0.1;
> = 1.5;

uniform float frost_amount<
    string label = "Frost grain";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 0.0;

// 0 = soft profile (edge², the original); 1 = iOS-like circular convex profile.
// The circular profile packs almost all the displacement into the last pixels of the rim, so
// the background gets "squeezed and wrapped" along the edge and the glass looks thick, not flat.
uniform float bezel_profile<
    string label = "Bezel profile (0 soft, 1 iOS convex)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 0.0;

// How much the tint fades toward the rim (0 = even tint; 1 = no tint at the edge).
// Why: in iOS, very dark glass (search bar, Siri) still reads as glass because the bezel shows
// the bright, refracted background even when the center is nearly black. With an even tint,
// a strong black tint turns the piece into a flat black blob.
uniform float tint_edge<
    string label = "Bezel tint (1 = fades out)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 0.0;

// How much highlight the rim side facing away from the light gets. It used to be a hard-coded
// 0.4. iOS varies: Control Center buttons light two opposite sides (~0.7), dark bars barely
// light the far side (~0.3). 0 = highlight only on the light side.
uniform float back_light<
    string label = "Back light";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 1.0; float step = 0.01;
> = 0.4;

// Fast texture-free hash for sample rotation and the frost effect.
// Why not the classic frac(sin(dot(p, ...)) * 43758.5453): with pixel coordinates the argument
// to sin() reaches ~150,000, and on many GPUs (Intel, some AMD, OpenGL in general) sin() loses
// precision at that scale, so the "noise" shows visible patterns or stripes.
// This hash (Dave Hoskins, "Hash without Sine") only uses frac/multiplies, so it looks the
// same on any GPU and backend (D3D11 or OpenGL).
float hash12(float2 p)
{
    float3 p3 = frac(float3(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

// Signed distance to a rounded rectangle (negative inside)
float sdRoundBox(float2 p, float2 b, float r)
{
    float2 q = abs(p) - b + float2(r, r);
    return length(max(q, float2(0.0, 0.0))) + min(max(q.x, q.y), 0.0) - r;
}

// Disc blur with 32 samples on a golden-angle spiral and Gaussian weights.
// Why 32 and not 16: at large radii, 16 samples are so far apart that instead of a blur you
// see sharp overlapping "copies" (blocks and stripes). The Gaussian weight makes the outer
// ring, which gives the copies away the most, contribute little, like a real blur.
float3 sampleBlur(float2 uv, float radius_px, float rot_offset)
{
    if (radius_px < 0.5)
        return image.Sample(textureSampler, uv).rgb;

    float3 acc = float3(0.0, 0.0, 0.0);
    float w_sum = 0.0;
    float fi = 0.0;
    for (int i = 0; i < 32; i++) {
        float a = fi * 2.39996323 + rot_offset;
        float t = sqrt((fi + 0.5) / 32.0);          // 0..1, uniform spread over the disc
        float w = exp(-2.5 * t * t);                // Gaussian: the disc edge weighs ~8%
        float2 o = float2(cos(a), sin(a)) * (t * radius_px) * uv_pixel_interval;
        acc += image.Sample(textureSampler, uv + o).rgb * w;
        w_sum += w;
        fi += 1.0;
    }
    return acc / w_sum;
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

    // Outside the panel: soft shadow shifted downward
    float ds = sdRoundBox(p - float2(0.0, shadow_size * 0.35), half_size, r);
    float sh = (1.0 - smoothstep(0.0, max(shadow_size, 0.001), ds)) * shadow_opacity;
    float3 outside = base.rgb * (1.0 - sh);

    if (d > 1.0)
        return float4(outside, base.a);

    // Smooth analytic bezel normal (avoids 4 extra sdRoundBox calls and 45° creases)
    float r_bezel = min(max(r, bezel), min(half_size.x, half_size.y));
    float2 q_n = abs(p) - half_size + float2(r_bezel, r_bezel);
    float2 n_corner = max(q_n, float2(0.0, 0.0));
    float2 n_inside = (q_n.x > q_n.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
    float2 n_dir = (length(n_corner) > 0.0001) ? n_corner : n_inside;
    float2 sgn = float2(p.x >= 0.0 ? 1.0 : -1.0, p.y >= 0.0 ? 1.0 : -1.0);
    float2 n = (n_dir * sgn) / max(length(n_dir), 0.0001);

    // 1 right at the edge, 0 in the flat center area
    float edge = 1.0 - saturate(-d / max(bezel, 1.0));
    // Circular profile: 1 - sqrt(1 - edge²) is the "height" of a quarter circle; its slope
    // shoots up at the rim, which is where iOS squeezes the background.
    float lens_circ = 1.0 - sqrt(saturate(1.0 - edge * edge));
    float lens = lerp(edge * edge, lens_circ, bezel_profile);

    // Optional liquid wave on the glass and the normal
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

    // Refraction: the bezel shows displaced content, like the edge of a convex piece of glass
    float2 disp_px = n * (refraction * lens) + wave_offset_px;
    float2 disp = disp_px * uv_pixel_interval;

    // Per-pixel noise for frost (rotates the blur disc and adds subtle grain).
    // Uses p (relative to the panel center), not pos (absolute on screen), so the grain sticks
    // to the glass: if the panel is animated (Move Transition, etc.) the frost moves with it
    // instead of looking like a fixed texture the panel slides over.
    float noise = hash12(p);
    float rot = (frost_amount > 0.001) ? (noise * 6.2831853 * saturate(frost_amount * 2.0)) : 0.0;

    // Optimization: a single blur pass when this pixel has no visible dispersion
    float3 col;
    if (dispersion < 0.001 || length(disp_px) * dispersion < 0.15) {
        col = sampleBlur(uv + disp, blur_radius, rot);
    } else {
        col.r = sampleBlur(uv + disp * (1.0 + dispersion), blur_radius, rot).r;
        col.g = sampleBlur(uv + disp, blur_radius, rot).g;
        col.b = sampleBlur(uv + disp * (1.0 - dispersion), blur_radius, rot).b;
    }

    // Saturation, tint and frost grain
    float lum = dot(col, float3(0.2126, 0.7152, 0.0722));
    col = lerp(float3(lum, lum, lum), col, saturation);
    // edge is 1 at the rim and 0 in the flat area: the tint is only reduced inside the bezel
    col = lerp(col, tint_color.rgb, tint_amount * (1.0 - tint_edge * edge));
    if (frost_amount > 0.001)
        col += (noise - 0.5) * frost_amount * 0.12;

    // Specular rim highlight based on the light direction
    float ang = radians(light_angle + light_speed * elapsed_time);
    float2 L = float2(cos(ang), -sin(ang));
    // back_light replaces the hard-coded 0.4: at 0 the highlight is only on the light side
    float facing = max(dot(n, L), 0.0) + back_light * max(dot(n, -L), 0.0);
    float rim = pow(edge, 4.0) * facing;
    float edge_line = 1.0 - smoothstep(0.0, 1.5, -d);   // thin 1-2 px edge line
    col += highlight * (rim * 0.45 + edge_line * 0.25 * (back_light + facing));

    // Antialiased edge
    float aa = saturate(0.5 - d);
    return float4(lerp(outside, saturate(col), aa), base.a);
}

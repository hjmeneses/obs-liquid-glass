// Liquid Glass with its shape defined by another source (OBS Studio + obs-shaderfilter)
//
// Usage:
//   1. Create a separate scene, e.g. "Glass Shape", with the shapes where you want glass
//      (transparent PNG, text, cropped solid color, etc.). That scene doesn't need to go live.
//   2. In your main scene, add the "User-defined shader" filter with this file.
//   3. Set "Shape source" to the "Glass Shape" scene.
// Wherever the shape is opaque (or white, in luminance mode) you get glass refracting the main scene.

uniform texture2d shape_source<
    string label = "Shape source";
>;

uniform bool use_luminance<
    string label = "Use luminance instead of alpha (white = glass)";
> = false;

uniform float blur_radius<
    string label = "Blur (px)";
    string widget_type = "slider";
    float minimum = 0.0; float maximum = 40.0; float step = 0.5;
> = 10.0;

uniform float bezel<
    string label = "Bezel width (px)";
    string widget_type = "slider";
    float minimum = 1.0; float maximum = 120.0; float step = 1.0;
> = 30.0;

uniform float refraction<
    string label = "Refraction (px, negative = magnifier)";
    string widget_type = "slider";
    float minimum = -150.0; float maximum = 150.0; float step = 1.0;
> = 45.0;

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
    float minimum = 1.0; float maximum = 120.0; float step = 1.0;
> = 30.0;

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

// Shape coverage at a point: 0 = no glass, 1 = glass
float shapeAt(float2 uv)
{
    float4 s = shape_source.Sample(textureSampler, uv);
    if (use_luminance)
        return saturate(dot(s.rgb, float3(0.2126, 0.7152, 0.0722)));
    return s.a;
}

// Blurred shape, used to cast the outer shadow
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

// Computes the outward normal (xy) and smooth height (z) of the bezel in a single pass.
// Uses 32 samples with a radial cone weight to remove the stepping that finite differences
// produced on hard edges.
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

// Main scene blur: 32 spiral samples with Gaussian weights.
// Why 32 and not 16: at large radii, 16 samples are so far apart that instead of a blur you
// see sharp overlapping "copies" (blocks and stripes). The Gaussian weight makes the outer
// ring, which gives the copies away the most, contribute little, like a real blur.
float3 sceneBlur(float2 uv, float radius_px, float rot_offset)
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

    // Shadow: only evaluated when the pixel isn't 100% covered by glass
    float3 outside = base.rgb;
    if (cover < 0.999 && shadow_opacity > 0.001) {
        float shadow_h = heightAt(uv - float2(0.0, shadow_size * 0.35) * uv_pixel_interval, shadow_size);
        outside = base.rgb * (1.0 - shadow_h * shadow_opacity * (1.0 - cover));
    }

    if (cover <= 0.001)
        return float4(outside, base.a);

    // Glass height and smooth normal in a single pass (33 reads instead of 85)
    float3 b = bevelAt(uv, max(bezel, 1.0));
    float2 n = b.xy;
    float h = b.z;

    float edge = saturate((1.0 - h) * 2.0);   // 1 at the edge, 0 in the flat area
    // Circular profile: 1 - sqrt(1 - edge²) is the "height" of a quarter circle; its slope
    // shoots up at the rim, which is where iOS squeezes the background.
    float lens_circ = 1.0 - sqrt(saturate(1.0 - edge * edge));
    float lens = lerp(edge * edge, lens_circ, bezel_profile);

    // Optional liquid wave on the glass and the normal
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
        // Note: in the flat center bevelAt returns n = (0,0), so here nw = w * k and normalizing
        // it yields a unit vector pointing in an arbitrary direction. That's harmless because
        // edge = 0 there, and lens, rim and edge_glint (the only things that use n) are 0. If you
        // ever use n outside the bezel, multiply by edge first or check length(b.xy) before normalizing.
        float2 nw = n + w * saturate(liquid_wave * 0.015);
        n = nw / max(length(nw), 0.0001);
    }

    // Bezel refraction with color dispersion
    float2 disp_px = n * (refraction * lens) + wave_offset_px;
    float2 disp = disp_px * uv_pixel_interval;

    // Per-pixel noise for frost (rotates the blur disc and adds subtle grain).
    // Here the grain uses pos (absolute on screen) on purpose: the shape comes from another source
    // and the shader doesn't know where it is or how it moves, so there's no local origin to anchor to.
    // Consequence: if you animate the shape source, the glass slides over a fixed frost pattern.
    float noise = hash12(pos);
    float rot = (frost_amount > 0.001) ? (noise * 6.2831853 * saturate(frost_amount * 2.0)) : 0.0;

    // Optimization: a single blur pass when this pixel has no visible dispersion
    float3 col;
    if (dispersion < 0.001 || length(disp_px) * dispersion < 0.15) {
        col = sceneBlur(uv + disp, blur_radius, rot);
    } else {
        col.r = sceneBlur(uv + disp * (1.0 + dispersion), blur_radius, rot).r;
        col.g = sceneBlur(uv + disp, blur_radius, rot).g;
        col.b = sceneBlur(uv + disp * (1.0 - dispersion), blur_radius, rot).b;
    }

    // Saturation, tint and frost grain
    float lum = dot(col, float3(0.2126, 0.7152, 0.0722));
    col = lerp(float3(lum, lum, lum), col, saturation);
    // edge is 1 at the rim and 0 in the flat area: the tint is only reduced inside the bezel
    col = lerp(col, tint_color.rgb, tint_amount * (1.0 - tint_edge * edge));
    if (frost_amount > 0.001)
        col += (noise - 0.5) * frost_amount * 0.12;

    // Specular highlight based on the light direction
    float ang = radians(light_angle + light_speed * elapsed_time);
    float2 L = float2(cos(ang), -sin(ang));
    // back_light replaces the hard-coded 0.4: at 0 the highlight is only on the light side
    float facing = max(dot(n, L), 0.0) + back_light * max(dot(n, -L), 0.0);
    float rim = pow(edge, 4.0) * facing;
    float edge_glint = smoothstep(0.85, 1.0, edge);
    col += highlight * (rim * 0.45 + edge_glint * 0.2 * (back_light + facing));

    return float4(lerp(outside, saturate(col), cover), base.a);
}

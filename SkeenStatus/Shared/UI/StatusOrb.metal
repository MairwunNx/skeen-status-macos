#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// A living orb: layered sine waves drift inside a soft sphere, tinted
// between two colors of one family (greens, yellows, or reds).
[[ stitchable ]] half4 statusOrb(
    float2 position,
    half4 color,
    float2 size,
    float time,
    half4 base,
    half4 accent,
    float energy
) {
    float2 uv = (position - size * 0.5) / (min(size.x, size.y) * 0.5);
    float r = length(uv);
    if (r > 1.0) { return half4(0.0); }

    // Waves: rotated sines warp the plane, then bands of light flow across it.
    float t = time * (0.35 + 0.65 * energy);
    float2 p = uv * 2.2;
    p += 0.35 * float2(sin(p.y * 1.7 + t * 1.1), cos(p.x * 1.9 - t * 0.9));
    p += 0.25 * float2(sin(p.y * 3.1 - t * 1.7), cos(p.x * 2.6 + t * 1.3));
    float w = sin(p.x * 1.6 + p.y * 1.1 + t * 1.5) * 0.5
            + sin(length(p + float2(sin(t * 0.6), cos(t * 0.4))) * 3.2 - t * 2.2) * 0.5;
    w = w * 0.5 + 0.5;

    half3 tint = mix(base.rgb, accent.rgb, half(smoothstep(0.2, 0.85, w)));
    // Bright crests where the bands meet, like light through water.
    float crest = pow(max(0.0, 1.0 - abs(w - 0.62) * 5.0), 3.0);
    tint += accent.rgb * half(crest * 0.75);

    // Shading: a lit sphere with a rim and a highlight up and to the left.
    float z = sqrt(max(0.0, 1.0 - r * r));
    float light = 0.55 + 0.45 * dot(normalize(float3(uv, z)), normalize(float3(-0.45, -0.6, 0.85)));
    float rim = smoothstep(0.55, 1.0, r) * 0.35;
    float highlight = pow(max(0.0, 1.0 - length(uv - float2(-0.35, -0.42)) * 1.9), 3.0) * 0.55;

    half3 rgb = tint * half(light) + half3(highlight) + tint * half(rim);
    float alpha = 1.0 - smoothstep(0.94, 1.0, r);
    return half4(rgb * half(alpha), half(alpha));
}

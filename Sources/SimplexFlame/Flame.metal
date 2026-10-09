#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float2 resolution;
    float time;
    float grain;
    float brightness;
    float darkMode;
    float2 fieldResolution;
};

struct VertexOut {
    float4 position [[position]];
};

vertex VertexOut fullscreenVertex(uint id [[vertex_id]]) {
    float2 p = float2((id << 1) & 2, id & 2);
    return {float4(p * 2.0 - 1.0, 0.0, 1.0)};
}

float hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Gradient noise: smooth in space, with no texture or frame-to-frame randomness.
float noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f*f*f*(f*(f*6.0-15.0)+10.0);
    float a = hash(i) * 6.2831853;
    float b = hash(i + float2(1,0)) * 6.2831853;
    float c = hash(i + float2(0,1)) * 6.2831853;
    float d = hash(i + float2(1,1)) * 6.2831853;
    return mix(mix(dot(float2(cos(a),sin(a)),f),
                   dot(float2(cos(b),sin(b)),f-float2(1,0)),u.x),
               mix(dot(float2(cos(c),sin(c)),f-float2(0,1)),
                   dot(float2(cos(d),sin(d)),f-1.0),u.x),u.y);
}

float fbm(float2 p) {
    float value = 0.0, amplitude = 0.57;
    for (int i=0; i<4; i++) {
        value += amplitude * noise(p);
        p = float2(0.8*p.x-0.6*p.y,0.6*p.x+0.8*p.y)*2.03 + 7.1;
        amplitude *= 0.48;
    }
    return value;
}

float flameField(float2 uv, constant Uniforms &u) {
    float aspect = u.resolution.x/u.resolution.y;
    // Keep the composition centered when switching between display shapes.
    float2 p = float2((uv.x-0.5)*aspect/1.51+0.5,uv.y);
    float t = u.time;
    float2 drift = float2(t*0.045,-t*0.027);
    float2 warp = float2(fbm(p*2.5+drift),fbm(p*2.5+float2(8.3,2.7)-drift*0.7));
    float2 q = p + warp*0.32;
    q.x += 0.035*sin(t*0.09+p.y*4.0);

    float boundary = 0.35 + 0.115*sin(q.x*6.4+0.5 + 0.15*sin(t*0.07));
    boundary += 0.22*exp(-pow((q.x-1.08)/0.26,2.0));
    float field = (boundary-q.y)*3.6;
    field += 0.20*fbm(q*4.0+drift*0.45);
    // Long warm fold on the left and a detached, softly melting tongue on the right.
    field += 0.65*exp(-pow((q.x-0.345)/0.038,2.0)-pow((q.y-0.48)/0.19,2.0));
    float tongue = exp(-pow((q.x-1.02)/0.33,2.0)-pow((q.y-0.64)/0.14,2.0));
    field += 1.75*tongue;
    // Cool pool in the upper center, with hot edges.
    field -= 0.40*exp(-pow((q.x-0.04)/0.24,2.0)-pow(q.y/0.5,2.0));
    return field;
}

float4 flameColor(float field, float2 position, constant Uniforms &u) {
    float grit = hash(floor(position));
    float grit2 = hash(floor(position)+float2(413,79));
    float granularField = field + (grit-0.5)*0.23*u.grain*mix(0.30,1.0,u.darkMode);
    // A clean daylight base with soft coral, peach, and muted teal folds.
    // Keep the original night colors and grain strength intact.
    float3 charcoal = mix(float3(0.965,0.970,0.975),float3(0.038,0.045,0.050),u.darkMode);
    float3 red = mix(float3(0.80,0.49,0.45),float3(0.98,0.045,0.018),u.darkMode);
    float3 orange = mix(float3(0.93,0.73,0.59),float3(1.0,0.48,0.115),u.darkMode);
    float3 teal = mix(float3(0.59,0.73,0.73),float3(0.16,0.35,0.38),u.darkMode);
    float3 deepTeal = mix(float3(0.36,0.55,0.59),float3(0.06,0.18,0.21),u.darkMode);
    float3 color = mix(charcoal,red,smoothstep(-0.13,0.19,granularField));
    color = mix(color,orange,smoothstep(0.17,0.48,granularField));
    color = mix(color,teal,smoothstep(0.52,0.95,granularField));
    color = mix(color,deepTeal,smoothstep(1.05,1.75,granularField));
    // In daylight, fade subtle texture into the shapes so the base stays clear.
    float surfaceGrain = u.grain*mix(0.22*smoothstep(-0.13,0.19,field),1.0,u.darkMode);
    color += (grit2-0.5)*0.105*surfaceGrain;
    color *= 1.0+(grit-0.5)*0.20*surfaceGrain;
    color = clamp(color*u.brightness,0.0,1.0);
    // Palette values are sRGB; the render target handles linear-to-sRGB encoding.
    color = select(color/12.92,pow((color+0.055)/1.055,float3(2.4)),color>0.04045);
    return float4(color,1.0);
}

// Retained as a full-resolution reference for visual and performance comparisons.
fragment float4 flameFragment(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    return flameColor(flameField(in.position.xy/u.resolution,u),in.position.xy,u);
}

// Only the smooth scalar field is reduced. A one-texel border keeps interpolation
// correct at the screen edges, instead of stretching the first/last sample.
fragment float fieldFragment(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 uv = (in.position.xy-1.0)/(u.fieldResolution-2.0);
    return flameField(uv,u);
}

fragment float4 compositeFragment(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]],
                                  texture2d<float> fieldTexture [[texture(0)]]) {
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = in.position.xy/u.resolution;
    float2 sampleUV = (uv*(u.fieldResolution-2.0)+1.0)/u.fieldResolution;
    float field = fieldTexture.sample(linearSampler,sampleUV).r;
    return flameColor(field,in.position.xy,u);
}

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct UBO
{
    float4x4 mvp;
    float2 window_size;
};

struct main0_out
{
    float4 frag_color [[user(locn0)]];
    float2 frag_uv [[user(locn1)]];
    float4 gl_Position [[position]];
};

struct main0_in
{
    float3 position [[attribute(0)]];
    float4 color [[attribute(1)]];
    float2 uv [[attribute(2)]];
};

vertex main0_out main0(main0_in in [[stage_in]], constant UBO& _21 [[buffer(0)]])
{
    main0_out out = {};
    float2 ndc_pos = ((in.position.xy * 2.0) / _21.window_size) - float2(1.0);
    out.gl_Position = _21.mvp * float4(ndc_pos, in.position.z, 1.0);
    out.frag_color = in.color;
    out.frag_uv = in.uv;
    return out;
}


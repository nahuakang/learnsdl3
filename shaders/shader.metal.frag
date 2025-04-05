#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct main0_out
{
    float4 out_color [[color(0)]];
};

struct main0_in
{
    float4 frag_color [[user(locn0)]];
    float2 frag_uv [[user(locn1)]];
};

fragment main0_out main0(main0_in in [[stage_in]], texture2d<float> tex_sampler [[texture(0)]], sampler tex_samplerSmplr [[sampler(0)]])
{
    main0_out out = {};
    bool _17 = in.frag_uv.x == 0.0;
    bool _24;
    if (_17)
    {
        _24 = in.frag_uv.y == 0.0;
    }
    else
    {
        _24 = _17;
    }
    bool _34;
    if (_24)
    {
        _34 = in.frag_color.w != 0.0;
    }
    else
    {
        _34 = _24;
    }
    if (_34)
    {
        out.out_color = in.frag_color;
    }
    else
    {
        out.out_color = tex_sampler.sample(tex_samplerSmplr, in.frag_uv) * in.frag_color;
    }
    return out;
}


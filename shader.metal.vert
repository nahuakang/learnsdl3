#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct main0_out
{
    float4 gl_Position [[position]];
};

vertex main0_out main0(uint gl_VertexIndex [[vertex_id]])
{
    main0_out out = {};
    if (int(gl_VertexIndex) == 0)
    {
        out.gl_Position = float4(-0.5, -0.5, 0.0, 1.0);
    }
    else
    {
        if (int(gl_VertexIndex) == 1)
        {
            out.gl_Position = float4(0.0, 0.5, 0.0, 1.0);
        }
        else
        {
            if (int(gl_VertexIndex) == 2)
            {
                out.gl_Position = float4(0.5, -0.5, 0.0, 1.0);
            }
        }
    }
    return out;
}


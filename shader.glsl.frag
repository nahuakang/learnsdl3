#version 460

layout(location=0) in vec4 frag_color;
layout(location=1) in vec2 frag_uv;

layout(set=2, binding=0) uniform sampler2D tex_sampler;

layout(location=0) out vec4 out_color;

void main() {
	// If texture coordinates are zero, use color only (for untextured meshes)
    if (frag_uv.x == 0.0 && frag_uv.y == 0.0 && frag_color.w != 0.0) {
        out_color = frag_color;
    } else {
		out_color = texture(tex_sampler, frag_uv) * frag_color;
    }
}
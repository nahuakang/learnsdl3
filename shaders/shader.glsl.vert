#version 460

layout(set=1, binding=0) uniform UBO {
	mat4 mvp;
	vec2 window_size;
};

layout(location=0) in vec3 position;
layout(location=1) in vec4 color;
layout(location=2) in vec2 uv;

layout(location=0) out vec4 frag_color;
layout(location=1) out vec2 frag_uv;

void main() {
	// Convert window coordinates to NDC
	vec2 ndc_pos = 2.0 * position.xy / window_size - 1.0;
	
	gl_Position = mvp * vec4(ndc_pos, position.z, 1.0);
	frag_color = color;
	frag_uv = uv;
}

#version 460

void main() {
	if (gl_VertexIndex == 0) {
		gl_Position = vec4(-0.5, -0.5, 0, 1);
	} else  if (gl_VertexIndex == 1) {
		gl_Position = vec4(0, 0.5, 0, 1);
	} else if (gl_VertexIndex == 2) {
		gl_Position = vec4(0.5, -0.5, 0, 1);
	} else if (gl_VertexIndex == 3) {
        gl_Position = vec4(0.5, -0.5, 0, 1);
    } else if (gl_VertexIndex == 4) {
        gl_Position = vec4(1, 0.5, 0, 1);
    } else if (gl_VertexIndex == 5) {
        gl_Position = vec4(1.5, -0.5, 0, 1);
    }
}
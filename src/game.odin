package main

import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:path/filepath"
import "core:strings"
import im "shared:imgui"
import sdl "vendor:sdl3"
import stbi "vendor:stb/image"

EYE_HEIGHT :: 1
MOVE_SPEED :: 5
LOOK_SENSITIVITY :: 0.3
ROTATION_SPEED :: f32(90) * linalg.RAD_PER_DEG


UBO :: struct {
	mvp: Mat4,
}


Vertex_Data :: struct {
	pos:   Vec3,
	color: sdl.FColor,
	uv:    Vec2,
}


Mesh :: struct {
	vertex_buf:  ^sdl.GPUBuffer,
	index_buf:   ^sdl.GPUBuffer,
	num_indices: u32,
}


Model :: struct {
	using mesh: Mesh, // TODO(nahua): Temporary using
	texture:    ^sdl.GPUTexture,
}


game_init :: proc() {
	setup_pipeline()

	copy_cmd_buf := sdl.AcquireGPUCommandBuffer(g.gpu)
	copy_pass := sdl.BeginGPUCopyPass(copy_cmd_buf)

	g.model = load_model(copy_pass, "tractor-police.obj", "colormap.png")

	sdl.EndGPUCopyPass(copy_pass)
	ok := sdl.SubmitGPUCommandBuffer(copy_cmd_buf);sdl_assert(ok)

	g.rotate = true

	g.clear_color = sdl.FColor{0, 0.023, 0.133, 1}
	g.camera = {
		position = {0, EYE_HEIGHT, 3},
		target   = {0, EYE_HEIGHT, 0},
	}
}


game_update :: proc(delta_time: f32) {
	if im.Begin("Inspector") {
		im.Checkbox("Rotate", &g.rotate)
		im.ColorEdit3(
			"Clear color",
			transmute(^[3]f32)&g.clear_color,
			{.Float},
		)
	}
	im.End()

	// update game state
	if g.rotate do g.rotation += ROTATION_SPEED * delta_time
	update_camera(delta_time)
}


game_render :: proc(
	cmd_buf: ^sdl.GPUCommandBuffer,
	swapchain_tex: ^sdl.GPUTexture,
) {
	proj_mat := linalg.matrix4_perspective_f32(
		linalg.to_radians(f32(70)),
		f32(g.window_size.x) / f32(g.window_size.y),
		0.0001,
		1000,
	)
	view_mat := linalg.matrix4_look_at_f32(
		g.camera.position,
		g.camera.target,
		{0, 1, 0},
	)
	model_mat :=
		linalg.matrix4_translate_f32({0, 0, 0}) *
		linalg.matrix4_rotate_f32(g.rotation, {0, 1, 0})

	ubo := UBO {
		mvp = proj_mat * view_mat * model_mat,
	}

	color_target := sdl.GPUColorTargetInfo {
		texture     = swapchain_tex,
		load_op     = .CLEAR,
		clear_color = g.clear_color,
		store_op    = .STORE,
	}
	depth_target_info := sdl.GPUDepthStencilTargetInfo {
		texture     = g.depth_texture,
		load_op     = .CLEAR,
		clear_depth = 1,
		store_op    = .DONT_CARE,
	}
	render_pass := sdl.BeginGPURenderPass(
		cmd_buf,
		&color_target,
		1,
		&depth_target_info,
	)
	sdl.PushGPUVertexUniformData(cmd_buf, 0, &ubo, size_of(ubo))
	sdl.BindGPUGraphicsPipeline(render_pass, g.pipeline)
	sdl.BindGPUVertexBuffers(
		render_pass,
		0,
		&(sdl.GPUBufferBinding{buffer = g.model.vertex_buf}),
		1,
	)
	sdl.BindGPUIndexBuffer(render_pass, {buffer = g.model.index_buf}, ._16BIT)
	sdl.BindGPUFragmentSamplers(
		render_pass,
		0,
		&(sdl.GPUTextureSamplerBinding {
				texture = g.model.texture,
				sampler = g.sampler,
			}),
		1,
	)
	sdl.DrawGPUIndexedPrimitives(render_pass, g.model.num_indices, 1, 0, 0, 0)
	sdl.EndGPURenderPass(render_pass)
}


setup_pipeline :: proc() {
	vert_shader := load_shader(g.gpu, "shader.vert")
	frag_shader := load_shader(g.gpu, "shader.frag")

	vertex_attrs := []sdl.GPUVertexAttribute {
		{
			location = 0,
			format = .FLOAT3,
			offset = u32(offset_of(Vertex_Data, pos)),
		},
		{
			location = 1,
			format = .FLOAT4,
			offset = u32(offset_of(Vertex_Data, color)),
		},
		{
			location = 2,
			format = .FLOAT2,
			offset = u32(offset_of(Vertex_Data, uv)),
		},
	}

	g.pipeline = sdl.CreateGPUGraphicsPipeline(
	g.gpu,
	{
		vertex_shader = vert_shader,
		fragment_shader = frag_shader,
		primitive_type = .TRIANGLELIST,
		vertex_input_state = {
			num_vertex_buffers = 1,
			vertex_buffer_descriptions = &(sdl.GPUVertexBufferDescription {
					slot = 0,
					pitch = size_of(Vertex_Data),
				}),
			num_vertex_attributes = u32(len(vertex_attrs)),
			vertex_attributes = raw_data(vertex_attrs),
		},
		depth_stencil_state = {
			enable_depth_test = true,
			enable_depth_write = true,
			compare_op = .LESS,
		},
		rasterizer_state = {
			cull_mode = .BACK,
			// fill_mode = .LINE,
		},
		target_info = {
			num_color_targets = 1,
			color_target_descriptions = &(sdl.GPUColorTargetDescription {
					format = g.swapchain_texture_format,
				}),
			has_depth_stencil_target = true,
			depth_stencil_format = g.depth_texture_format,
		},
	},
	)

	sdl.ReleaseGPUShader(g.gpu, vert_shader)
	sdl.ReleaseGPUShader(g.gpu, frag_shader)

	g.sampler = sdl.CreateGPUSampler(g.gpu, {})
}


update_camera :: proc(dt: f32) {
	move_input: Vec2
	if g.key_down[.W] do move_input.y = 1
	else if g.key_down[.S] do move_input.y = -1
	if g.key_down[.A] do move_input.x = -1
	else if g.key_down[.D] do move_input.x = 1

	look_input := g.mouse_move * LOOK_SENSITIVITY

	g.look.yaw = math.wrap(g.look.yaw - look_input.x, 360)
	g.look.pitch = math.clamp(g.look.pitch - look_input.y, -89, 89)

	look_mat := linalg.matrix3_from_yaw_pitch_roll_f32(
		linalg.to_radians(g.look.yaw),
		linalg.to_radians(g.look.pitch),
		0,
	)

	forward := look_mat * Vec3{0, 0, -1}
	right := look_mat * Vec3{1, 0, 0}
	move_dir := forward * move_input.y + right * move_input.x
	move_dir.y = 0

	motion := linalg.normalize0(move_dir) * MOVE_SPEED * dt

	g.camera.position += motion
	g.camera.target = g.camera.position + forward
}

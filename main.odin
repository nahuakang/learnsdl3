package main

import "base:runtime"
import "core:log"
import "core:math/linalg"
import "core:mem"
import "core:strings"
import sdl "vendor:sdl3"

/* CONSTANTS */
ROTATION_SPEED := linalg.to_radians(f32(90))


/* VARIABLES */
default_context: runtime.Context


/* TYPES */
Vec3 :: [3]f32
Vertex_Data :: struct {
	pos:   Vec3,
	color: sdl.FColor,
}

Mesh :: struct {
	vertex_buffer: ^sdl.GPUBuffer,
	index_buffer: ^sdl.GPUBuffer,
	index_count: u32,
	index_element_size: sdl.GPUIndexElementSize,
	position: Vec3,
	rotation_axis: Vec3,
	rotation_speed_multiplier:f32,
}

UBO :: struct {
	mvp: matrix[4, 4]f32,
}

when ODIN_OS == .Windows {
	GPU_SHADER_FORMAT: sdl.GPUShaderFormat = {.SPIRV}
	entrypoint := "main"
	frag_shader_code := #load("shader.spv.frag")
	vert_shader_code := #load("shader.spv.vert")
} else when ODIN_OS == .Darwin {
	GPU_SHADER_FORMAT: sdl.GPUShaderFormat = {.MSL}
	entrypoint := "main0"
	frag_shader_code := #load("shader.metal.frag")
	vert_shader_code := #load("shader.metal.vert")
}

create_mesh :: proc(
	gpu: ^sdl.GPUDevice, 
	vertices: []Vertex_Data,
	indices: []u16,
	position: Vec3,
	rotation_axis: Vec3 = {0, 1, 0},
	rotation_speed_multiplier: f32 = 1.0
) -> Mesh {
	vertices_byte_size := len(vertices) * size_of(Vertex_Data)
	indices_byte_size := len(indices) * size_of(u16)

	vertex_buf := sdl.CreateGPUBuffer(gpu, {usage = {.VERTEX}, size = u32(vertices_byte_size)})
	index_buf := sdl.CreateGPUBuffer(gpu, {usage = {.INDEX}, size = u32(indices_byte_size)})

	vertex_transfer_buf := sdl.CreateGPUTransferBuffer(gpu, {
		usage = .UPLOAD, size = u32(vertices_byte_size),
	})
	index_transfer_buf := sdl.CreateGPUTransferBuffer(gpu, {
		usage = .UPLOAD, size = u32(indices_byte_size),
	})

	vertex_transfer_mem := sdl.MapGPUTransferBuffer(device = gpu, transfer_buffer = vertex_transfer_buf, cycle=false)
	mem.copy(dst = vertex_transfer_mem, src = raw_data(vertices), len = vertices_byte_size)
	sdl.UnmapGPUTransferBuffer(device = gpu, transfer_buffer = vertex_transfer_buf)

	index_transfer_mem := sdl.MapGPUTransferBuffer(device = gpu, transfer_buffer = index_transfer_buf, cycle = false)
	mem.copy(dst = index_transfer_mem, src = raw_data(indices), len = indices_byte_size)
	sdl.UnmapGPUTransferBuffer(device = gpu, transfer_buffer = index_transfer_buf)

	copy_cmd_buf := sdl.AcquireGPUCommandBuffer(gpu)
	copy_pass := sdl.BeginGPUCopyPass(copy_cmd_buf)
	sdl.UploadToGPUBuffer(copy_pass=copy_pass, source={transfer_buffer=vertex_transfer_buf}, destination={buffer=vertex_buf, size=u32(vertices_byte_size)}, cycle=false)
	sdl.UploadToGPUBuffer(copy_pass=copy_pass, source={transfer_buffer=index_transfer_buf}, destination={buffer=index_buf, size=u32(indices_byte_size)}, cycle=false)
	sdl.EndGPUCopyPass(copy_pass)
	ok := sdl.SubmitGPUCommandBuffer(copy_cmd_buf);assert(ok)
	sdl.ReleaseGPUTransferBuffer(gpu, vertex_transfer_buf)
	sdl.ReleaseGPUTransferBuffer(gpu, index_transfer_buf)

	return Mesh{
		vertex_buffer = vertex_buf,
		index_buffer = index_buf,
		index_count = u32(len(indices)),
		index_element_size = ._16BIT,
		position = position,
		rotation_axis = rotation_axis,
		rotation_speed_multiplier = rotation_speed_multiplier,
	}
}

destroy_mesh :: proc(gpu: ^sdl.GPUDevice, mesh: ^Mesh) {
	sdl.ReleaseGPUBuffer(gpu, mesh.vertex_buffer)
	sdl.ReleaseGPUBuffer(gpu, mesh.index_buffer)
}


main :: proc() {
	context.logger = log.create_console_logger()
	default_context = context

	sdl.SetLogPriorities(.VERBOSE)
	sdl.SetLogOutputFunction(
		proc "c" (
			userdata: rawptr,
			category: sdl.LogCategory,
			priority: sdl.LogPriority,
			message: cstring,
		) {
			context = default_context
			log.debugf("SDL {} [{}]: {}", category, priority, message)
		},
		nil,
	)

	ok := sdl.Init({.VIDEO});assert(ok)

	window := sdl.CreateWindow("Hello SDL3", 1280, 780, {});assert(window != nil)

	gpu := sdl.CreateGPUDevice(GPU_SHADER_FORMAT, true, nil);assert(gpu != nil)

	ok = sdl.ClaimWindowForGPUDevice(gpu, window);assert(ok)

	vert_shader := load_shader(gpu, vert_shader_code, .VERTEX, 1)
	frag_shader := load_shader(gpu, frag_shader_code, .FRAGMENT, 0)

	// Define triangle mesh data
	triangle_vertices := []Vertex_Data {
		{pos = {-0.5, -0.5, 0}, color = {1, 0, 0, 1}},
		{pos = {0, 0.5, 0}, color = {0, 1, 0, 1}},
		{pos = {0.5, -0.5, 0}, color = {0, 0, 1, 1}},
	}
	triangle_indices := []u16{
		0, 1, 2,
	}
	// Define quad mesh data
	quad_vertices := []Vertex_Data {
		{pos = {-0.5, -0.5, 0}, color = {1, 1, 0, 1}},
		{pos = {-0.5, 0.5, 0}, color = {1, 0, 1, 1}},
		{pos = {0.5, 0.5, 0}, color = {0, 1, 1, 1}},
		{pos = {0.5, -0.5, 0}, color = {0.5, 0.5, 1, 1}},
	}
	quad_indices := []u16{
		0, 1, 2,
		0, 2, 3,
	}

	triangle_mesh := create_mesh(
		gpu,
		triangle_vertices,
		triangle_indices,
		position = {-1.5, 0, -5},
		rotation_axis = {0, 1, 0},
		rotation_speed_multiplier = 1.0,
	)
	quad_mesh := create_mesh(
		gpu,
		quad_vertices,
		quad_indices,
		position = {1.5, 0, -5},
		rotation_axis = {0, 1, 1},
		rotation_speed_multiplier = 0.7,
	)
	meshes := []Mesh{triangle_mesh, quad_mesh}

	vertex_attrs := []sdl.GPUVertexAttribute {
		{location = 0, format = .FLOAT3, offset = u32(offset_of(Vertex_Data, pos))},
		{location = 1, format = .FLOAT4, offset = u32(offset_of(Vertex_Data, color))},
	}

	pipeline := sdl.CreateGPUGraphicsPipeline(
		gpu,
		{
			vertex_shader = vert_shader,
			fragment_shader = frag_shader,
			primitive_type = .TRIANGLELIST,
			vertex_input_state = {
				num_vertex_buffers = 1,
				vertex_buffer_descriptions = &(
					sdl.GPUVertexBufferDescription {
						slot=0,
						pitch = size_of(Vertex_Data)
					}
				),
				num_vertex_attributes = u32(len(vertex_attrs)),
				vertex_attributes = raw_data(vertex_attrs),
			},
			target_info = {
				num_color_targets = 1,
				color_target_descriptions = &(sdl.GPUColorTargetDescription {
						format = sdl.GetGPUSwapchainTextureFormat(gpu, window),
					}),
			},
		},
	)

	sdl.ReleaseGPUShader(gpu, vert_shader)
	sdl.ReleaseGPUShader(gpu, frag_shader)

	win_size: [2]i32
	ok = sdl.GetWindowSize(window, &win_size.x, &win_size.y);assert(ok)

	rotation := f32(0)
	proj_mat := linalg.matrix4_perspective_f32(
		linalg.to_radians(f32(70)),
		f32(win_size.x) / f32(win_size.y),
		0.0001,
		1000,
	)
	last_ticks := sdl.GetTicks()

	main_loop: for {
		new_ticks := sdl.GetTicks()
		delta_time := f32(new_ticks - last_ticks) / 1000
		last_ticks = new_ticks

		// process events
		ev: sdl.Event
		for sdl.PollEvent(&ev) {
			#partial switch ev.type {
			case .QUIT:
				break main_loop
			case .KEY_DOWN:
				if ev.key.scancode == .ESCAPE do break main_loop
			}
		}

		// update game state
		rotation += ROTATION_SPEED * delta_time

		// render
		cmd_buf := sdl.AcquireGPUCommandBuffer(gpu)
		swapchain_tex: ^sdl.GPUTexture
		ok = sdl.WaitAndAcquireGPUSwapchainTexture(
			cmd_buf,
			window,
			&swapchain_tex,
			nil,
			nil,
		);assert(ok)

		if swapchain_tex != nil {
			color_target := sdl.GPUColorTargetInfo {
				texture     = swapchain_tex,
				load_op     = .CLEAR,
				clear_color = {0, 0.2, 0.4, 1},
				store_op    = .STORE,
			}
			render_pass := sdl.BeginGPURenderPass(cmd_buf, &color_target, 1, nil)
			sdl.BindGPUGraphicsPipeline(render_pass, pipeline)

			for mesh in meshes {
				mesh_rotation := rotation * mesh.rotation_speed_multiplier
				model_mat := linalg.matrix4_translate_f32(mesh.position) * linalg.matrix4_rotate_f32(mesh_rotation, mesh.rotation_axis)
				ubo := UBO {
					mvp = proj_mat * model_mat,
				}
				sdl.BindGPUVertexBuffers(render_pass, 0, &(sdl.GPUBufferBinding{buffer = mesh.vertex_buffer}), 1)
				sdl.BindGPUIndexBuffer(render_pass, {buffer = mesh.index_buffer}, mesh.index_element_size)
				sdl.PushGPUVertexUniformData(cmd_buf, 0, &ubo, size_of(ubo))
				sdl.DrawGPUIndexedPrimitives(
					render_pass,
					num_indices = mesh.index_count,
					num_instances = 1,
					first_index = 0,
					vertex_offset = 0,
					first_instance = 0,
				)
			}
			
			sdl.EndGPURenderPass(render_pass)
		}

		ok = sdl.SubmitGPUCommandBuffer(cmd_buf);assert(ok)
	}
}

load_shader :: proc(
	device: ^sdl.GPUDevice,
	code: []u8,
	stage: sdl.GPUShaderStage,
	num_uniform_buffers: u32,
) -> ^sdl.GPUShader {
	return sdl.CreateGPUShader(
		device,
		{
			code_size = len(code),
			code = raw_data(code),
			entrypoint = strings.clone_to_cstring(entrypoint),
			format = GPU_SHADER_FORMAT,
			stage = stage,
			num_uniform_buffers = num_uniform_buffers,
		},
	)
}

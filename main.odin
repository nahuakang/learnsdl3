package main

import "base:runtime"
import "core:log"
import "core:math/linalg"
import "core:mem"
import "core:strings"
import sdl "vendor:sdl3"
import stbi "vendor:stb/image"


/* CONSTANTS */
ROTATION_SPEED := linalg.to_radians(f32(90))
WHITE := sdl.FColor{1, 1, 1, 1}


/* VARIABLES */
default_context: runtime.Context


/* TYPES */
Vec3 :: [3]f32
Vertex_Data :: struct {
	pos:   Vec3,
	color: sdl.FColor,
	uv:    [2]f32,
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

	vert_shader := load_shader(
		gpu,
		vert_shader_code,
		.VERTEX,
		num_uniform_buffers = 1,
		num_samplers = 0,
	)
	frag_shader := load_shader(
		gpu,
		frag_shader_code,
		.FRAGMENT,
		num_uniform_buffers = 0,
		num_samplers = 1,
	)

	img_size: [2]i32
	pixels := stbi.load(
		"cobblestone_1.png",
		&img_size.x,
		&img_size.y,
		nil,
		4,
	);assert(pixels != nil)
	pixels_byte_size := img_size.x * img_size.y * 4

	texture := sdl.CreateGPUTexture(
		device = gpu,
		createinfo = sdl.GPUTextureCreateInfo {
			format = .R8G8B8A8_UNORM,
			usage = {.SAMPLER},
			width = u32(img_size.x),
			height = u32(img_size.y),
			layer_count_or_depth = 1,
			num_levels = 1,
		},
	)
	sampler := sdl.CreateGPUSampler(device = gpu, createinfo = sdl.GPUSamplerCreateInfo{})

	// VERTEX DATA COPYING
	// Vertex data
	vertices := []Vertex_Data {
		{pos = {-0.5, 0.5, 0}, color = WHITE, uv = {0, 0}}, // tl
		{pos = {0.5, 0.5, 0}, color = WHITE, uv = {1, 0}}, // tr
		{pos = {-0.5, -0.5, 0}, color = WHITE, uv = {0, 1}}, // bl
		{pos = {0.5, -0.5, 0}, color = WHITE, uv = {1, 1}}, // br
	}
	vertices_byte_size := len(vertices) * size_of(Vertex_Data)
	// Index data
	indices := []u16{0, 1, 2, 2, 1, 3}
	indices_byte_size := len(indices) * size_of(indices[0])

	// The actual GPU-side buffer that will be used for rendering
	vertex_buf := sdl.CreateGPUBuffer(
		device = gpu,
		createinfo = {usage = {.VERTEX}, size = u32(vertices_byte_size)},
	)
	index_buf := sdl.CreateGPUBuffer(
		device = gpu,
		createinfo = {usage = {.INDEX}, size = u32(indices_byte_size)},
	)
	// A staging buffer in a memory type that allows CPU access; transfer from CPU to GPU
	transfer_buf := sdl.CreateGPUTransferBuffer(
		device = gpu,
		createinfo = {usage = .UPLOAD, size = u32(vertices_byte_size + indices_byte_size)},
	)
	// A pointer to the mapped memory of the transfer buffer, which allows the CPU to write directly to it
	transfer_mem := transmute([^]byte)sdl.MapGPUTransferBuffer(
		device = gpu,
		transfer_buffer = transfer_buf,
		cycle = false,
	)
	mem.copy(dst = transfer_mem, src = raw_data(vertices), len = vertices_byte_size)
	mem.copy(
		dst = transfer_mem[vertices_byte_size:],
		src = raw_data(indices),
		len = indices_byte_size,
	)
	sdl.UnmapGPUTransferBuffer(device = gpu, transfer_buffer = transfer_buf)

	tex_transfer_buf := sdl.CreateGPUTransferBuffer(
		device = gpu,
		createinfo = sdl.GPUTransferBufferCreateInfo {
			usage = .UPLOAD,
			size = u32(pixels_byte_size),
		},
	)
	tex_transfer_mem := sdl.MapGPUTransferBuffer(gpu, tex_transfer_buf, false)
	mem.copy(tex_transfer_mem, pixels, int(pixels_byte_size))
	sdl.UnmapGPUTransferBuffer(gpu, tex_transfer_buf)

	// Copy Command Buffer
	copy_cmd_buf := sdl.AcquireGPUCommandBuffer(gpu)
	copy_pass := sdl.BeginGPUCopyPass(copy_cmd_buf)
	sdl.UploadToGPUBuffer(
		copy_pass = copy_pass,
		source = sdl.GPUTransferBufferLocation{transfer_buffer = transfer_buf},
		destination = sdl.GPUBufferRegion{buffer = vertex_buf, size = u32(vertices_byte_size)},
		cycle = false,
	)
	sdl.UploadToGPUBuffer(
		copy_pass = copy_pass,
		source = sdl.GPUTransferBufferLocation {
			transfer_buffer = transfer_buf,
			offset = u32(vertices_byte_size),
		},
		destination = sdl.GPUBufferRegion{buffer = index_buf, size = u32(indices_byte_size)},
		cycle = false,
	)
	sdl.UploadToGPUTexture(
		copy_pass = copy_pass,
		source = sdl.GPUTextureTransferInfo{transfer_buffer = tex_transfer_buf},
		destination = sdl.GPUTextureRegion {
			texture = texture,
			w = u32(img_size.x),
			h = u32(img_size.y),
			d = 1,
		},
		cycle = false,
	)
	sdl.EndGPUCopyPass(copy_pass)
	ok = sdl.SubmitGPUCommandBuffer(copy_cmd_buf);assert(ok)
	sdl.ReleaseGPUTransferBuffer(gpu, transfer_buf)
	sdl.ReleaseGPUTransferBuffer(gpu, tex_transfer_buf)

	vertex_attrs := []sdl.GPUVertexAttribute {
		{location = 0, format = .FLOAT3, offset = u32(offset_of(Vertex_Data, pos))},
		{location = 1, format = .FLOAT4, offset = u32(offset_of(Vertex_Data, color))},
		{location = 2, format = .FLOAT2, offset = u32(offset_of(Vertex_Data, uv))},
	}

	pipeline := sdl.CreateGPUGraphicsPipeline(
		gpu,
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
	UBO :: struct {
		mvp: matrix[4, 4]f32,
	}
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

		// Update rotation
		rotation += ROTATION_SPEED * delta_time
		model_mat :=
			linalg.matrix4_translate_f32({0, 0, -2}) *
			linalg.matrix4_rotate_f32(rotation, {0, 1, 0})
		ubo := UBO {
			mvp = proj_mat * model_mat,
		}

		if swapchain_tex != nil {
			color_target := sdl.GPUColorTargetInfo {
				texture     = swapchain_tex,
				load_op     = .CLEAR,
				clear_color = {0, 0.2, 0.4, 1},
				store_op    = .STORE,
			}
			render_pass := sdl.BeginGPURenderPass(cmd_buf, &color_target, 1, nil)
			sdl.BindGPUGraphicsPipeline(render_pass, pipeline)
			sdl.BindGPUVertexBuffers(
				render_pass = render_pass,
				first_slot = 0,
				bindings = &(sdl.GPUBufferBinding{buffer = vertex_buf}),
				num_bindings = 1,
			)
			sdl.BindGPUIndexBuffer(
				render_pass = render_pass,
				binding = {buffer = index_buf},
				index_element_size = ._16BIT,
			)
			sdl.PushGPUVertexUniformData(cmd_buf, 0, &ubo, size_of(ubo))
			sdl.BindGPUFragmentSamplers(
				render_pass = render_pass,
				first_slot = 0,
				texture_sampler_bindings = &(sdl.GPUTextureSamplerBinding {
						texture = texture,
						sampler = sampler,
					}),
				num_bindings = 1,
			)
			sdl.DrawGPUIndexedPrimitives(render_pass, 6, 1, 0, 0, 0)
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
	num_samplers: u32,
) -> ^sdl.GPUShader {
	return sdl.CreateGPUShader(
		device = device,
		createinfo = sdl.GPUShaderCreateInfo {
			code_size = len(code),
			code = raw_data(code),
			entrypoint = strings.clone_to_cstring(entrypoint),
			format = GPU_SHADER_FORMAT,
			stage = stage,
			num_uniform_buffers = num_uniform_buffers,
			num_samplers = num_samplers,
		},
	)
}

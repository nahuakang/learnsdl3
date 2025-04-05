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


/* GRAPHICS TYPES */
Vec3 :: [3]f32
Vertex_Data :: struct {
	pos:   Vec3,
	color: sdl.FColor,
	uv:    [2]f32,
}


UBO :: struct {
	mvp:         matrix[4, 4]f32,
	window_size: [2]f32,
}

when ODIN_OS == .Windows {
	GPU_SHADER_FORMAT: sdl.GPUShaderFormat = {.SPIRV}
	entrypoint := "main"
	frag_shader_code := #load("../shaders/shader.spv.frag")
	vert_shader_code := #load("../shaders/shader.spv.vert")
} else when ODIN_OS == .Darwin {
	GPU_SHADER_FORMAT: sdl.GPUShaderFormat = {.MSL}
	entrypoint := "main0"
	frag_shader_code := #load("../shaders/shader.metal.frag")
	vert_shader_code := #load("../shaders/shader.metal.vert")
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
	// sdl.SetWindowFullscreen(window, true)

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

	cobblestone_texture := load_texture(device = gpu, file_name = "assets/cobblestone_1.png")
	office_texture := load_texture(device = gpu, file_name = "assets/office.png")

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
	log.log(log.Level.Info, "Window width: %v", win_size.x)
	log.log(log.Level.Info, "Window height: %v", win_size.y)

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
		ok = sdl.GetWindowSize(window, &win_size.x, &win_size.y);assert(ok)

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

		if swapchain_tex != nil {
			color_target := sdl.GPUColorTargetInfo {
				texture     = swapchain_tex,
				load_op     = .CLEAR,
				clear_color = {0, 0.2, 0.4, 1},
				store_op    = .STORE,
			}
			render_pass := sdl.BeginGPURenderPass(cmd_buf, &color_target, 1, nil)
			sdl.BindGPUGraphicsPipeline(render_pass, pipeline)

			// Draw texture to fit window
			win_size: [2]i32
			ok := sdl.GetWindowSize(window, &win_size.x, &win_size.y);assert(ok)
			// Calculate scale to fill window while maintaining aspect ratio
			scale_x := f32(win_size.x) / f32(office_texture.size.x)
			scale_y := f32(win_size.y) / f32(office_texture.size.y)
			scale := max(scale_x, scale_y)
			// Calculate scaled dimensions
			scaled_width := f32(office_texture.size.x) * scale
			scaled_height := f32(office_texture.size.y) * scale

			// Center the texture in the window
			pos_x := (f32(win_size.x) - scaled_width) / 2
			pos_y := (f32(win_size.y) - scaled_height) / 2

			draw_texture(
				device = gpu,
				render_pass = render_pass,
				command_buffer = cmd_buf,
				window = window,
				texture = office_texture,
				pos_x = pos_x,
				pos_y = pos_y,
				tint = WHITE,
				scale = scale,
			)

			draw_texture(
				device = gpu,
				render_pass = render_pass,
				command_buffer = cmd_buf,
				window = window,
				texture = cobblestone_texture,
				pos_x = 100,
				pos_y = 100,
				scale = 0.2,
			)

			draw_texture(
				device = gpu,
				render_pass = render_pass,
				command_buffer = cmd_buf,
				window = window,
				texture = cobblestone_texture,
				pos_x = 500,
				pos_y = 500,
				scale = 0.2,
			)

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

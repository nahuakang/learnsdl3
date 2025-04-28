package main

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"
import sdl "vendor:sdl3"
import stbi "vendor:stb/image"


/* CONSTANTS */
CONTENT_DIR :: "content"
DEPTH_TEXTURE_FORMAT :: sdl.GPUTextureFormat.D24_UNORM
ROTATION_SPEED := linalg.to_radians(f32(90))
WHITE := sdl.FColor{1, 1, 1, 1}

/* CAMERA-RELATED */
EYE_HEIGHT :: 1
LOOK_SENSITIVITY :: 1.0 / 10.0
MOVE_SPEED :: 5

/* VARIABLES */
default_context: runtime.Context
depth_texture: ^sdl.GPUTexture
gpu: ^sdl.GPUDevice
pipeline: ^sdl.GPUGraphicsPipeline
sampler: ^sdl.GPUSampler
window: ^sdl.Window
win_size: [2]i32

camera: Camera
look: Look
key_down: KeyDown
mouse_move: MouseMove

/* TYPES */
/* CAMERA-RELATED */
Camera :: struct {
	position: Vec3,
	target:   Vec3,
}
Look :: struct {
	yaw:   f32,
	pitch: f32,
}
KeyDown :: #sparse[sdl.Scancode]bool
MouseMove :: Vec2

/* MODEL-RELATED */
Model :: struct {
	vertex_buf:  ^sdl.GPUBuffer,
	index_buf:   ^sdl.GPUBuffer,
	num_indices: u32,
	texture:     ^sdl.GPUTexture,
}
UBO :: struct {
	mvp: matrix[4, 4]f32,
}
Vec3 :: [3]f32
Vec2 :: [2]f32
Vertex_Data :: struct {
	pos:   Vec3,
	color: sdl.FColor,
	uv:    Vec2,
}

when ODIN_OS == .Windows {
	GPU_SHADER_FORMAT: sdl.GPUShaderFormat = {.SPIRV}
	entrypoint := "main"
} else when ODIN_OS == .Darwin {
	GPU_SHADER_FORMAT: sdl.GPUShaderFormat = {.MSL}
	entrypoint := "main0"
}


init :: proc() {
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

	window = sdl.CreateWindow("Hello SDL3", 1280, 780, {});assert(window != nil)

	gpu = sdl.CreateGPUDevice(GPU_SHADER_FORMAT, true, nil);assert(gpu != nil)

	ok = sdl.ClaimWindowForGPUDevice(gpu, window);assert(ok)

	ok = sdl.GetWindowSize(window, &win_size.x, &win_size.y);assert(ok)

	// Simple depth texture with a specific depth format; width and height will be of our render target (win_size)
	// If the window must be resizable, then we need to create this depth texture each time we change the window size
	depth_texture = sdl.CreateGPUTexture(
		gpu,
		{
			format = DEPTH_TEXTURE_FORMAT,
			usage = {.DEPTH_STENCIL_TARGET},
			width = u32(win_size.x),
			height = u32(win_size.y),
			layer_count_or_depth = 1,
			num_levels = 1,
		},
	)

	camera = Camera {
		position = {0, EYE_HEIGHT, 3}, // 3m further away from the origin
		target   = {0, EYE_HEIGHT, 0},
	}

	// Hide mouse and constrain to the window
	_ = sdl.SetWindowRelativeMouseMode(window, true)
}


setup_pipeline :: proc() {
	vert_shader := load_shader(gpu, "shader.vert", num_uniform_buffers = 1, num_samplers = 0)
	frag_shader := load_shader(gpu, "shader.frag", num_uniform_buffers = 0, num_samplers = 1)

	vertex_attrs := []sdl.GPUVertexAttribute {
		{location = 0, format = .FLOAT3, offset = u32(offset_of(Vertex_Data, pos))},
		{location = 1, format = .FLOAT4, offset = u32(offset_of(Vertex_Data, color))},
		{location = 2, format = .FLOAT2, offset = u32(offset_of(Vertex_Data, uv))},
	}

	pipeline = sdl.CreateGPUGraphicsPipeline(
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
			depth_stencil_state = {
				enable_depth_test  = true,
				enable_depth_write = true,
				compare_op         = .LESS, // Pixels closer to the camera have lower (less) value than those farther away
			},
			// Cull back-facing triangles with the rasterizer state so we don't render faces inside a model
			// There are also other settings in GPURasterizerState 
			rasterizer_state = {
				cull_mode = .BACK,
				// fill_mode = .LINE, // See the model in wireframe mode
			},
			target_info = {
				num_color_targets = 1,
				color_target_descriptions = &(sdl.GPUColorTargetDescription {
						format = sdl.GetGPUSwapchainTextureFormat(gpu, window),
					}),
				has_depth_stencil_target = true,
				depth_stencil_format = DEPTH_TEXTURE_FORMAT,
			},
		},
	)

	sdl.ReleaseGPUShader(gpu, vert_shader)
	sdl.ReleaseGPUShader(gpu, frag_shader)

	sampler = sdl.CreateGPUSampler(device = gpu, createinfo = sdl.GPUSamplerCreateInfo{})
}


load_model :: proc(mesh_file: string, texture_file: string) -> Model {
	mesh_path := filepath.join({CONTENT_DIR, "meshes", mesh_file}, context.temp_allocator)
	texture_path := filepath.join({CONTENT_DIR, "textures", texture_file}, context.temp_allocator)
	texture_file := strings.clone_to_cstring(texture_path, context.temp_allocator)

	img_size: [2]i32
	// the obj file uv's Y-coordinates are inverted: instead of 0 at the top and 1 at the bottom,
	// it's inverted so 0 is at the bottom and 1 on the top. stbi provides a functionality to flip it:
	stbi.set_flip_vertically_on_load(1)
	fmt.printfln("texture_file: %", texture_file)
	pixels := stbi.load(texture_file, &img_size.x, &img_size.y, nil, 4);assert(pixels != nil)
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
	obj_data := obj_load(mesh_path)

	vertices := make([]Vertex_Data, len(obj_data.faces))
	indices := make([]u16, len(obj_data.faces))

	for face, i in obj_data.faces {
		uv := obj_data.uvs[face.uv]
		vertices[i] = {
			pos   = obj_data.positions[face.pos],
			color = WHITE,
			uv    = {uv.x, uv.y},
		}
		indices[i] = u16(i)
	}

	obj_destroy(obj_data)

	num_indices := len(indices)

	vertices_byte_size := len(vertices) * size_of(vertices[0])
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
	delete(indices)
	delete(vertices)

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

	ok := sdl.SubmitGPUCommandBuffer(copy_cmd_buf);assert(ok)
	sdl.ReleaseGPUTransferBuffer(gpu, transfer_buf)
	sdl.ReleaseGPUTransferBuffer(gpu, tex_transfer_buf)

	return Model {
		vertex_buf = vertex_buf,
		index_buf = index_buf,
		num_indices = u32(num_indices),
		texture = texture,
	}
}


update_camera :: proc(dt: f32) {
	move_input: Vec2
	if key_down[.W] do move_input.y = 1
	else if key_down[.S] do move_input.y = -1

	if key_down[.A] do move_input.x = -1
	else if key_down[.D] do move_input.x = 1

	look_input := mouse_move * LOOK_SENSITIVITY

	// Why look.yaw - mouse_move.x:
	// Mouse movement to the right is positive; positive angle will rotate to the left
	// So we need to invert it to actually rotate right when the mouse_move is to the right
	look.yaw = math.wrap(look.yaw - look_input.x, 360)
	// -89 to 89 to avoid problems with Euler angles and extreme pitch angles
	// Use quaternions for more complex features
	look.pitch = math.clamp(look.pitch - look_input.y, -89, 89)

	look_mat := linalg.matrix3_from_yaw_pitch_roll_f32(
		linalg.to_radians(look.yaw),
		linalg.to_radians(look.pitch),
		0,
	)

	forward := look_mat * Vec3{0, 0, -1}
	right := look_mat * Vec3{1, 0, 0}
	move_dir := forward * move_input.y + right * move_input.x
	move_dir.y = 0 // Cancel out vertical movement

	motion := linalg.normalize0(move_dir) * MOVE_SPEED * dt

	camera.position += motion
	camera.target = camera.position + forward
}


main :: proc() {
	context.logger = log.create_console_logger()
	default_context = context

	init()
	setup_pipeline()
	model := load_model("tractor-police.obj", "colormap.png")

	rotation := f32(0)
	proj_mat := linalg.matrix4_perspective_f32(
		linalg.to_radians(f32(70)),
		f32(win_size.x) / f32(win_size.y),
		0.0001,
		1000,
	)
	last_ticks := sdl.GetTicks()

	main_loop: for {
		free_all(context.temp_allocator)
		mouse_move = MouseMove{}

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
				key_down[ev.key.scancode] = true
			case .KEY_UP:
				key_down[ev.key.scancode] = false
			case .MOUSE_MOTION:
				mouse_move += {ev.motion.xrel, ev.motion.yrel}
			}
		}

		// update game state
		rotation += ROTATION_SPEED * delta_time
		update_camera(delta_time)

		// render
		cmd_buf := sdl.AcquireGPUCommandBuffer(gpu)
		swapchain_tex: ^sdl.GPUTexture
		ok := sdl.WaitAndAcquireGPUSwapchainTexture(
			cmd_buf,
			window,
			&swapchain_tex,
			nil,
			nil,
		);assert(ok)

		view_mat := linalg.matrix4_look_at_f32(camera.position, camera.target, {0, 1, 0})
		model_mat :=
			linalg.matrix4_translate_f32({0, 0, 0}) *
			linalg.matrix4_rotate_f32(rotation, {0, 1, 0})
		ubo := UBO {
			mvp = proj_mat * view_mat * model_mat,
		}

		if swapchain_tex != nil {
			color_target := sdl.GPUColorTargetInfo {
				texture     = swapchain_tex,
				load_op     = .CLEAR,
				clear_color = {0, 0.2, 0.4, 1},
				store_op    = .STORE,
			}
			depth_target_info := sdl.GPUDepthStencilTargetInfo {
				texture     = depth_texture,
				load_op     = .CLEAR, // Clear for rendering a new frame
				clear_depth = 1, // 1 since everything we want to draw has a depth value smaller than 1
				store_op    = .DONT_CARE,
			}
			render_pass := sdl.BeginGPURenderPass(cmd_buf, &color_target, 1, &depth_target_info)
			sdl.PushGPUVertexUniformData(cmd_buf, 0, &ubo, size_of(ubo))
			sdl.BindGPUGraphicsPipeline(render_pass, pipeline)
			sdl.BindGPUVertexBuffers(
				render_pass = render_pass,
				first_slot = 0,
				bindings = &(sdl.GPUBufferBinding{buffer = model.vertex_buf}),
				num_bindings = 1,
			)
			sdl.BindGPUIndexBuffer(
				render_pass = render_pass,
				binding = {buffer = model.index_buf},
				index_element_size = ._16BIT,
			)
			sdl.BindGPUFragmentSamplers(
				render_pass = render_pass,
				first_slot = 0,
				texture_sampler_bindings = &(sdl.GPUTextureSamplerBinding {
						texture = model.texture,
						sampler = sampler,
					}),
				num_bindings = 1,
			)
			sdl.DrawGPUIndexedPrimitives(render_pass, model.num_indices, 1, 0, 0, 0)
			sdl.EndGPURenderPass(render_pass)
		}

		ok = sdl.SubmitGPUCommandBuffer(cmd_buf);assert(ok)
	}
}


load_shader :: proc(
	device: ^sdl.GPUDevice,
	shaderfile: string,
	num_uniform_buffers: u32,
	num_samplers: u32,
) -> ^sdl.GPUShader {
	stage: sdl.GPUShaderStage
	switch filepath.ext(shaderfile) {
	case ".vert":
		stage = .VERTEX
	case ".frag":
		stage = .FRAGMENT
	}
	shaderfile := filepath.join(
		{CONTENT_DIR, "shaders", "out", shaderfile},
		context.temp_allocator,
	)
	filename := strings.concatenate({shaderfile, ".spv"})
	code, ok := os.read_entire_file_from_filename(filename, context.temp_allocator);assert(ok)

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

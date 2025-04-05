package main

import "core:math/linalg"
import "core:mem"
import sdl "vendor:sdl3"
import stbi "vendor:stb/image"


Texture2D :: struct {
	texture: ^sdl.GPUTexture,
	sampler: ^sdl.GPUSampler,
	size:    [2]i32,
}


// load_texture loads texture from file into GPU memory (VRAM)s
load_texture :: proc(device: ^sdl.GPUDevice, file_name: cstring) -> Texture2D {
	texture: Texture2D

	pixels := stbi.load(file_name, &texture.size.x, &texture.size.y, nil, 4);assert(pixels != nil)
	pixels_byte_size := texture.size.x * texture.size.y * 4

	texture.texture = sdl.CreateGPUTexture(
		device = device,
		createinfo = sdl.GPUTextureCreateInfo {
			format = .R8G8B8A8_UNORM,
			usage = {.SAMPLER},
			width = u32(texture.size.x),
			height = u32(texture.size.y),
			layer_count_or_depth = 1,
			num_levels = 1,
		},
	)
	texture.sampler = sdl.CreateGPUSampler(
		device = device,
		createinfo = sdl.GPUSamplerCreateInfo{},
	)

	tex_transfer_buf := sdl.CreateGPUTransferBuffer(
		device = device,
		createinfo = sdl.GPUTransferBufferCreateInfo {
			usage = .UPLOAD,
			size = u32(pixels_byte_size),
		},
	)
	tex_transfer_mem := sdl.MapGPUTransferBuffer(device, tex_transfer_buf, false)
	mem.copy(tex_transfer_mem, pixels, int(pixels_byte_size))
	sdl.UnmapGPUTransferBuffer(device, tex_transfer_buf)

	// Copy Command Buffer
	copy_cmd_buf := sdl.AcquireGPUCommandBuffer(device)
	copy_pass := sdl.BeginGPUCopyPass(copy_cmd_buf)
	sdl.UploadToGPUTexture(
		copy_pass = copy_pass,
		source = sdl.GPUTextureTransferInfo{transfer_buffer = tex_transfer_buf},
		destination = sdl.GPUTextureRegion {
			texture = texture.texture,
			w = u32(texture.size.x),
			h = u32(texture.size.y),
			d = 1,
		},
		cycle = false,
	)
	sdl.EndGPUCopyPass(copy_pass)
	ok := sdl.SubmitGPUCommandBuffer(copy_cmd_buf);assert(ok)
	sdl.ReleaseGPUTransferBuffer(device, tex_transfer_buf)

	return texture
}


// draw_texture draws a Texture2D
draw_texture :: proc(
	device: ^sdl.GPUDevice,
	render_pass: ^sdl.GPURenderPass,
	command_buffer: ^sdl.GPUCommandBuffer,
	window: ^sdl.Window,
	texture: Texture2D,
	pos_x: f32,
	pos_y: f32,
	tint: sdl.FColor,
) {
	win_size: [2]i32
	ok := sdl.GetWindowSize(window, &win_size.x, &win_size.y);assert(ok)

	rotation := f32(0)
	proj_mat := linalg.matrix4_perspective_f32(
		linalg.to_radians(f32(70)),
		f32(win_size.x) / f32(win_size.y),
		0.0001,
		1000,
	)
	model_mat :=
		linalg.matrix4_translate_f32({0, 0, -2}) * linalg.matrix4_rotate_f32(rotation, {0, 1, 0})
	ubo := UBO {
		mvp = proj_mat * model_mat,
	}

	vertices := []Vertex_Data {
		{pos = {pos_x, pos_y + 1, 0}, color = tint, uv = {0, 0}}, // tl
		{pos = {pos_x + 1, pos_y + 1, 0}, color = tint, uv = {1, 0}}, // tr
		{pos = {pos_x, pos_y, 0}, color = tint, uv = {0, 1}}, // bl
		{pos = {pos_x + 1, pos_y, 0}, color = tint, uv = {1, 1}}, // br
	}
	vertices_byte_size := len(vertices) * size_of(Vertex_Data)
	// Index data
	indices := []u16{0, 1, 2, 2, 1, 3}
	indices_byte_size := len(indices) * size_of(indices[0])

	// The actual GPU-side buffer that will be used for rendering
	vertex_buf := sdl.CreateGPUBuffer(
		device = device,
		createinfo = {usage = {.VERTEX}, size = u32(vertices_byte_size)},
	)
	index_buf := sdl.CreateGPUBuffer(
		device = device,
		createinfo = {usage = {.INDEX}, size = u32(indices_byte_size)},
	)
	// A staging buffer in a memory type that allows CPU access; transfer from CPU to GPU
	transfer_buf := sdl.CreateGPUTransferBuffer(
		device = device,
		createinfo = {usage = .UPLOAD, size = u32(vertices_byte_size + indices_byte_size)},
	)
	// A pointer to the mapped memory of the transfer buffer, which allows the CPU to write directly to it
	transfer_mem := transmute([^]byte)sdl.MapGPUTransferBuffer(
		device = device,
		transfer_buffer = transfer_buf,
		cycle = false,
	)
	mem.copy(dst = transfer_mem, src = raw_data(vertices), len = vertices_byte_size)
	mem.copy(
		dst = transfer_mem[vertices_byte_size:],
		src = raw_data(indices),
		len = indices_byte_size,
	)
	sdl.UnmapGPUTransferBuffer(device = device, transfer_buffer = transfer_buf)

	// Copy Command Buffer
	copy_cmd_buf := sdl.AcquireGPUCommandBuffer(device)
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

	sdl.EndGPUCopyPass(copy_pass)
	ok = sdl.SubmitGPUCommandBuffer(copy_cmd_buf);assert(ok)
	sdl.ReleaseGPUTransferBuffer(device, transfer_buf)

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
	sdl.PushGPUVertexUniformData(command_buffer, 0, &ubo, size_of(ubo))
	sdl.BindGPUFragmentSamplers(
		render_pass = render_pass,
		first_slot = 0,
		texture_sampler_bindings = &(sdl.GPUTextureSamplerBinding {
				texture = texture.texture,
				sampler = texture.sampler,
			}),
		num_bindings = 1,
	)
	sdl.DrawGPUIndexedPrimitives(render_pass, u32(len(indices)), 1, 0, 0, 0)
}

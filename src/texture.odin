package main

import "core:mem"
import sdl "vendor:sdl3"
import stbi "vendor:stb/image"


Texture :: struct {
	texture: ^sdl.GPUTexture,
	sampler: ^sdl.GPUSampler,
	size:    [2]i32,
}


load_texture :: proc(device: ^sdl.GPUDevice, file_name: cstring) -> Texture {
	texture: Texture

	pixels := stbi.load(
		file_name, //"assets/cobblestone_1.png",
		&texture.size.x,
		&texture.size.y,
		nil,
		4,
	);assert(pixels != nil)
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

package main

import "core:log"
import sdl "vendor:sdl3"

CONTENT_DIR :: "content"

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

Vec3 :: [3]f32
Vec2 :: [2]f32
Mat4 :: matrix[4, 4]f32
Quat :: quaternion128

WHITE :: sdl.FColor{1, 1, 1, 1}


sdl_assert :: proc(ok: bool) {
	if !ok do log.panicf("SDL Error: {}", sdl.GetError())
}


Globals :: struct {
	gpu:                      ^sdl.GPUDevice,
	window:                   ^sdl.Window,
	window_size:              [2]i32,
	depth_texture:            ^sdl.GPUTexture,
	depth_texture_format:     sdl.GPUTextureFormat,
	swapchain_texture_format: sdl.GPUTextureFormat,
	pipeline:                 ^sdl.GPUGraphicsPipeline,
	sampler:                  ^sdl.GPUSampler,
	key_down:                 KeyDown,
	mouse_move:               MouseMove,
	camera:                   Camera,
	look:                     Look,
	clear_color:              sdl.FColor,
	rotate:                   bool,
	rotation:                 f32,
	models:                   []Model,
	entities:                 []Entity,
}


g: Globals

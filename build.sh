#!/bin/bash

# Fail the script if any command fails
set -e

# Compile GLSL shaders to SPIR-V
glslc shaders/shader.glsl.frag -o shaders/shader.spv.frag
glslc shaders/shader.glsl.vert -o shaders/shader.spv.vert
# Cross-Compile SPIR-V to METAL
spirv-cross --msl shaders/shader.spv.frag --output shaders/shader.metal.frag
spirv-cross --msl shaders/shader.spv.vert --output shaders/shader.metal.vert

# Build Odin project
odin build src/ -debug -out:learnsdl3

# Optional run parameter
if [ "$1" = "run" ]; then
    ./learnsdl3
fi

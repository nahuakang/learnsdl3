#!/bin/bash

# Fail the script if any command fails
set -e

# Compile GLSL shaders to SPIR-V
glslc shader.glsl.frag -o shader.spv.frag
glslc shader.glsl.vert -o shader.spv.vert
# Cross-Compile SPIR-V to METAL
spirv-cross --msl shader.spv.frag --output shader.metal.frag
spirv-cross --msl shader.spv.vert --output shader.metal.vert

# Build Odin project
odin build . -debug -out:learnsdl3

# Optional run parameter
if [ "$1" = "run" ]; then
    ./learnsdl3
fi

@echo off
REM Compile GLSL shaders
glslc shaders/shader.glsl.frag -o shaders/shader.spv.frag
if %errorlevel% neq 0 exit /b 1

glslc shaders/shader.glsl.vert -o shaders/shader.spv.vert
if %errorlevel% neq 0 exit /b 1

REM Build Odin project exactly as you run it in terminal
odin build src/ -debug -out:learnsdl3.exe
if %errorlevel% neq 0 exit /b 1

REM Run the executable if "run" argument is provided
if "%~1" == "run" (
    learnsdl3.exe
)
@echo off
REM Compile GLSL shaders
glslc shader.glsl.frag -o shader.spv.frag
if %errorlevel% neq 0 exit /b 1

glslc shader.glsl.vert -o shader.spv.vert
if %errorlevel% neq 0 exit /b 1

REM Build Odin project exactly as you run it in terminal
odin build . -debug -out:learnsdl3.exe
if %errorlevel% neq 0 exit /b 1

REM Run the executable if "run" argument is provided
if "%~1" == "run" (
    learnsdl3.exe
)
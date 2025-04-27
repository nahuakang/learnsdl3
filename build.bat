@echo off
REM Compile GLSL shaders
shadercross content/shaders/src/shader.frag.hlsl -o content/shaders/out/shader.frag.spv
if %errorlevel% neq 0 exit /b 1

shadercross content/shaders/src/shader.vert.hlsl -o content/shaders/out/shader.vert.spv
if %errorlevel% neq 0 exit /b 1

REM Build Odin project exactly as you run it in terminal
odin build src -debug -out:learnsdl3.exe
if %errorlevel% neq 0 exit /b 1

REM Run the executable if "run" argument is provided
if "%~1" == "run" (
    learnsdl3.exe
)

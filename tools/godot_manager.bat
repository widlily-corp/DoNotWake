@echo off
rem Менеджер проектов Godot (без открытия проекта).
rem OpenGL на этой машине рисует пустое окно, поэтому принудительно Vulkan.
setlocal
set "GODOT_EXE=GODOT_BIN"
start "" "%GODOT_EXE%" --rendering-driver vulkan
endlocal

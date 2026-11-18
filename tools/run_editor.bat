@echo off
rem Запуск редактора Godot 4.7.2.
rem На этой машине OpenGL-рендер даёт чёрное окно, поэтому принудительно Vulkan.
setlocal
set "GODOT_EXE=GODOT_BIN"
set "PROJECT=%~dp0.."
start "" "%GODOT_EXE%" --editor --path "%PROJECT%" --rendering-driver vulkan
endlocal

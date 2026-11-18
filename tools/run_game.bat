@echo off
rem Запуск игры (главная сцена) без редактора.
setlocal
set "GODOT_EXE=GODOT_BIN"
set "PROJECT=%~dp0.."
start "" "%GODOT_EXE%" --path "%PROJECT%" --rendering-driver vulkan
endlocal

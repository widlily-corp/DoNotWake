@echo off
rem Open the project in the Godot 4.7.2 editor.
rem Vulkan is forced because the OpenGL renderer produces a black window here.
rem If Godot is not on PATH, set GODOT_BIN to the engine executable first.
setlocal
if not defined GODOT_BIN set "GODOT_BIN=godot.exe"
set "PROJECT=%~dp0.."
start "" %GODOT_BIN% --editor --path "%PROJECT%" --rendering-driver vulkan
endlocal

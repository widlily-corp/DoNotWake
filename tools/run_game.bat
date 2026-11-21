@echo off
rem Launch the game (main scene) without the editor.
rem If Godot is not on PATH, set GODOT_BIN to the engine executable first.
setlocal
if not defined GODOT_BIN set "GODOT_BIN=godot.exe"
set "PROJECT=%~dp0.."
start "" %GODOT_BIN% --path "%PROJECT%" --rendering-driver vulkan
endlocal

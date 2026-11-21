@echo off
rem Open the Godot project manager (no project loaded).
rem Vulkan is forced for the same reason as in run_editor.bat.
rem If Godot is not on PATH, set GODOT_BIN to the engine executable first.
setlocal
if not defined GODOT_BIN set "GODOT_BIN=godot.exe"
start "" %GODOT_BIN% --rendering-driver vulkan
endlocal

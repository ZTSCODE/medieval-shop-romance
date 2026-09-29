@echo off
set "GODOT_EXE=C:\Users\ZTCUS\Desktop\Godot.exe"
set "PROJECT_DIR=%~dp0.."
if not exist "%GODOT_EXE%" (
  echo Godot was not found. Import project.godot with Godot 4.7.1.
  pause
  exit /b 1
)
start "" "%GODOT_EXE%" --path "%PROJECT_DIR%"
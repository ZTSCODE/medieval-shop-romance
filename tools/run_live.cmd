@echo off
rem Starts the game in live mode: text and content changes show up without a restart.
rem See docs/knowledge/dev-live-reload.md.
start "" "C:\Users\ZTCUS\Desktop\Godot.exe" --path "%~dp0.." -- --live

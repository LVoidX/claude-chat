@echo off
rem The free local AI helper (Aider + a model running on this PC through Ollama). For small changes.
rem Type what you want changed, e.g.:  /add godot_world/scene/village.gd   then   make the well roof red
rem /undo takes back the last change, /exit quits.
cd /d "%~dp0"
set PATH=D:\Tools\bin;%PATH%
set OLLAMA_API_BASE=http://127.0.0.1:11434
aider %*

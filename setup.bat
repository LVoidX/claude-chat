@echo off
rem One-time setup for Claude Chat: installs what it needs and makes a desktop shortcut.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
pause

# One-time setup for Claude Chat (run setup.bat). Safe to run again.
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$godotDir = Join-Path (Split-Path -Parent $here) "godot"
$godotVersion = "4.7.2-stable"

function Step($text) { Write-Host ""; Write-Host "== $text" -ForegroundColor Cyan }

Step "Python"
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    Write-Host "Python is not installed. Install it from https://www.python.org/downloads/" -ForegroundColor Yellow
    Write-Host "(tick 'Add python.exe to PATH' in the installer), then run setup.bat again."
    exit 1
}
python --version

Step "Python packages (speech recognition)"
python -m pip install --user --upgrade numpy sounddevice faster-whisper
if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
    Write-Host "NVIDIA graphics card found: installing the GPU libraries for fast speech recognition."
    python -m pip install --user nvidia-cublas-cu12 "nvidia-cudnn-cu12==9.*"
} else {
    Write-Host "No NVIDIA card: speech recognition will run on the CPU (a bit slower, still fine)."
}

Step "Godot (the 3D world)"
if (Get-ChildItem $godotDir -Filter "Godot_v*_win64.exe" -ErrorAction SilentlyContinue) {
    Write-Host "Godot is already there."
} else {
    New-Item -ItemType Directory -Force $godotDir | Out-Null
    $zip = Join-Path $godotDir "godot.zip"
    $url = "https://github.com/godotengine/godot/releases/download/$godotVersion/Godot_v$($godotVersion)_win64.exe.zip"
    Write-Host "Downloading Godot $godotVersion (about 80 MB)..."
    Invoke-WebRequest $url -OutFile $zip -UseBasicParsing
    Expand-Archive $zip -DestinationPath $godotDir -Force
    Remove-Item $zip
    Write-Host "Godot installed in $godotDir"
}

Step "Claude Code"
$claude = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claude) {
    $claude = Get-ChildItem (Join-Path $env:APPDATA "Claude\claude-code") -Recurse -Filter claude.exe -ErrorAction SilentlyContinue | Select-Object -First 1
}
$localBin = Join-Path $env:USERPROFILE ".localin"
if (-not $claude -and (Test-Path (Join-Path $localBin "claude.exe"))) {
    $claude = Get-Item (Join-Path $localBin "claude.exe")
    if (-not (([Environment]::GetEnvironmentVariable("Path", "User")) -split ";" -contains $localBin)) {
        [Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path", "User") + ";$localBin", "User")
        Write-Host "Added $localBin to your PATH (open a new terminal to use 'claude')."
    }
}
if ($claude) {
    Write-Host "Claude Code found."
} else {
    Write-Host "Claude Code is not installed. In PowerShell run:  irm https://claude.ai/install.ps1 | iex" -ForegroundColor Yellow
    Write-Host "then run setup.bat again, and sign in once with:  claude auth login"
}

Step "Desktop shortcut"
$pythonw = Join-Path (Split-Path -Parent (Get-Command python).Source) "pythonw.exe"
if (-not (Test-Path $pythonw)) { $pythonw = "pythonw.exe" }
$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath("Desktop")) "Claude Chat.lnk"))
$link.TargetPath = $pythonw
$link.Arguments = '"' + (Join-Path $here "chat.pyw") + '"'
$link.WorkingDirectory = $here
$link.Save()
Write-Host "Made 'Claude Chat' on your desktop."

Write-Host ""
Write-Host "All set! Start it with the 'Claude Chat' shortcut (or Start.bat)." -ForegroundColor Green
Write-Host "If you have never used Claude Code before: open a terminal, run 'claude' once and sign in."

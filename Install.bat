@echo off
rem Installs or updates The Lost Expedition for TLauncher. Run it again to get updates.
rem REPO is the raw GitHub address of this folder.
set "REPO=https://raw.githubusercontent.com/oguzhan00yildiz/lost-expedition/main"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $s = Join-Path $env:TEMP 'lost-expedition-install.ps1'; Invoke-WebRequest '%REPO%/install.ps1' -OutFile $s -UseBasicParsing; & $s -Modlist '%REPO%/modlist.json'"
echo.
pause

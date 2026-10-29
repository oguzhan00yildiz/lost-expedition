@echo off
rem Installs or updates The Lost Expedition for TLauncher. Run it again to get updates.
rem REPO is the raw GitHub address of this folder.
set "REPO=https://raw.githubusercontent.com/oguzhan00yildiz/lost-expedition/main"

rem TLauncher puts TLauncher.exe in .minecraft. Ask only when it is missing.
if exist "%APPDATA%\.minecraft\TLauncher.exe" goto install
choice /c YN /n /m "Download TLauncher? Press Y for yes or N for no: "
if errorlevel 2 goto install
rem The TLauncher site blocks scripted downloads, so the browser downloads the installer.
start "" "https://tlauncher.org/installer"
echo.
echo Your browser now downloads the TLauncher installer.
echo If no download starts, get it from https://tlauncher.org
echo 1. Run the installer.
echo 2. Open TLauncher once, then close it.
echo 3. Come back here.
echo.
pause

:install
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $s = Join-Path $env:TEMP 'lost-expedition-install.ps1'; Invoke-WebRequest '%REPO%/install.ps1' -OutFile $s -UseBasicParsing; & $s -Modlist '%REPO%/modlist.json'"
echo.
pause

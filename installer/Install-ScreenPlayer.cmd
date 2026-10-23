@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-ScreenPlayer.ps1" -InstallerPath "%~dp0ScreenPlayer-Setup-@APP_VERSION@.exe"
set "installer_result=%ERRORLEVEL%"
if not "%installer_result%"=="0" pause
exit /b %installer_result%

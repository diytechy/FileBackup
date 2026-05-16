@echo off
REM Elevates and runs the USB partition setup. Required because Storage cmdlets need Admin.

setlocal
cd /d "%~dp0"

REM Quick admin check
net session >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo Requesting elevation...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "tests\Setup-USB.ps1" %*
pause

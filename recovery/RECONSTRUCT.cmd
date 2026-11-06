@echo off
where pwsh >nul 2>nul
if errorlevel 1 (
  echo PowerShell 7 is required. Install it locally, then retry this carried kit.
  if "%~1"=="" pause
  exit /b 2
)
if "%~1"=="" (
  pwsh -NoProfile -STA -File "%~dp0RECONSTRUCT.ps1" -Interactive -ExitCode
) else (
  pwsh -NoProfile -File "%~dp0RECONSTRUCT.ps1" -ExitCode %*
)
exit /b %errorlevel%

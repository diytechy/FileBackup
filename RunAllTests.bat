@echo off
REM ============================================================
REM FileBackup test runner - single-click entry point.
REM Usage: RunAllTests.bat [Backend] [extra Run-All.ps1 args]
REM   Backend = Subst (default) | VHDX | RealUSB
REM
REM First run: runs tests\Setup.ps1 which may prompt to install
REM System.IO.Hashing. Subsequent runs: silent.
REM Requires PowerShell 7+ (pwsh).
REM ============================================================

setlocal enabledelayedexpansion
cd /d "%~dp0"

REM PowerShell 7+ is required (Windows PowerShell 5.1 is not supported).
where pwsh >nul 2>&1 || (echo [ERR] pwsh ^(PowerShell 7+^) not found. Install: winget install Microsoft.PowerShell & exit /b 1)
set PS=pwsh

REM ---------- pre-flight ----------
if not exist "FileBackup.ps1"   (echo [ERR] FileBackup.ps1 missing & exit /b 1)
if not exist "Reconstruct.ps1"  (echo [ERR] Reconstruct.ps1 missing & exit /b 1)
if not exist "tests\Run-All.ps1"(echo [ERR] tests\Run-All.ps1 missing & exit /b 1)

REM ---------- setup (idempotent) ----------
if not exist "tests\.setup-complete" (
    echo Running first-time setup...
    %PS% -NoProfile -ExecutionPolicy Bypass -File "tests\Setup.ps1" -InstallDeps
    if errorlevel 1 (
        echo [ERR] Setup failed. & exit /b 1
    )
)

REM ---------- pick backend ----------
if "%~1"=="" (set BACKEND=Subst) else (set BACKEND=%~1 & shift)

echo.
echo ============================================
echo FileBackup tests - backend: %BACKEND%
echo ============================================

%PS% -NoProfile -ExecutionPolicy Bypass -File "tests\Run-All.ps1" ^
     -Backend %BACKEND% ^
     -ResultRoot "%TEMP%\FileBackupTests" ^
     -EmitJUnit %1 %2 %3 %4 %5

set RC=%ERRORLEVEL%

echo.
if %RC% equ 0 (
    echo [SUCCESS] All tests passed.
) else (
    echo [FAILURE] One or more tests failed - see results.csv above.
)
exit /b %RC%

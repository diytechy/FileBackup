@echo off
REM ============================================================
REM LEGACY runner for Test-Backup.ps1 - SUPERSEDED by RunAllTests.bat
REM (which drives the modular tests/ harness). Kept for reference only;
REM Test-Backup.ps1 predates the module split and is not maintained.
REM Use RunAllTests.bat instead.
REM ============================================================
REM FileBackup Test Suite Runner
REM Kicks off comprehensive test harness and reports results

setlocal enabledelayedexpansion

cd /d "%~dp0"

echo.
echo ========================================
echo FileBackup Test Suite
echo ========================================
echo.
echo Starting test run at %date% %time%
echo Working directory: %cd%
echo.

REM Check if 7-Zip is installed (needed for compression tests)
if exist "%ProgramFiles%\7-Zip\7z.exe" (
    echo [OK] 7-Zip found at %ProgramFiles%\7-Zip\7z.exe
) else (
    echo [WARN] 7-Zip not found. Compression tests may fail.
    echo        Install from: https://www.7-zip.org/
)

echo.
echo Checking for required files...
if not exist "FileBackup.ps1" (
    echo [ERROR] FileBackup.ps1 not found in %cd%
    exit /b 1
)
echo [OK] FileBackup.ps1 found

if not exist "Reconstruct.ps1" (
    echo [ERROR] Reconstruct.ps1 not found in %cd%
    exit /b 1
)
echo [OK] Reconstruct.ps1 found

if not exist "Test-Backup.ps1" (
    echo [ERROR] Test-Backup.ps1 not found in %cd%
    exit /b 1
)
echo [OK] Test-Backup.ps1 found

echo.
echo ========================================
echo Running Test Suite...
echo ========================================
echo.

REM Run the test suite
powershell -NoProfile -ExecutionPolicy Bypass -File "Test-Backup.ps1" -BackupScriptPath "FileBackup.ps1"
set TESTRESULT=%ERRORLEVEL%

echo.
echo ========================================
echo Test Run Complete
echo ========================================
echo.

if %TESTRESULT% equ 0 (
    echo [SUCCESS] Test suite completed without critical errors.
    echo.
    echo Check the following for detailed results:
    echo - Console output above for test-by-test results
    echo - CSV file in %%TEMP%%\BackupTest_* folder for structured results
) else (
    echo [FAILURE] Test suite encountered errors (exit code: %TESTRESULT%)
)

echo.
echo Completed at %date% %time%
echo.

exit /b %TESTRESULT%

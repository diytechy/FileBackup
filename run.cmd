@echo off
setlocal
REM Product launcher (Windows) — double-click to see FileBackup run.
REM Every launchable project ships run.cmd / run.sh (process.md section 7,
REM "the evaluator's rungs") so starting it never requires recalling a
REM command. Read it first; it only runs the one command below.

REM --- EDIT FOR YOUR PROJECT ---------------------------------------------------
REM Runs the self-contained DEMONSTRATION, not a formal backup: it creates a
REM scratch source tree under %%TEMP%%\FileBackupDemo, drives a create / modify /
REM remove / re-add / no-op backup timeline with the real engine, restores the
REM latest state AND every dated snapshot, byte-verifies everything (xxHash128),
REM and writes a narrative TimelineReport.md. Nothing outside that temp area is
REM touched, and no config file is needed. Args pass through, e.g.:
REM   run.cmd -Mode HashAddressed -Compress
REM
REM The FORMAL backup entry point is FileBackup.ps1 with your own config
REM (README "Quick start"); restore from a backup is its bundled RECONSTRUCT.bat.
REM The full gated test matrix is RunAllTests.bat / scripts\check.ps1.
set "RUN_CMD=pwsh -NoProfile -File scripts\demo_timeline.ps1"
REM ----------------------------------------------------------------------------

cd /d "%~dp0"
if not defined RUN_CMD (
  echo run.cmd: no launch command wired yet.
  echo Edit RUN_CMD in this file — see the EDIT FOR YOUR PROJECT block — and
  echo in run.sh. The README "Run it" section documents the underlying command.
  pause
  exit /b 1
)
echo Running: %RUN_CMD% %*
%RUN_CMD% %*
set "EXITCODE=%ERRORLEVEL%"
echo.
echo Exited with code %EXITCODE%.
pause
exit /b %EXITCODE%

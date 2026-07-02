@echo off
setlocal
REM Product launcher (Windows) — double-click to run this project.
REM Every launchable project ships run.cmd / run.sh / run.command (process.md
REM section 7, "the evaluator's rungs") so starting it never requires recalling
REM a command. Read it first; it only runs the one command below.
REM
REM Not applicable (a pure library)? Delete the run.* launchers and describe
REM usage in README.md instead.

REM --- EDIT FOR YOUR PROJECT ---------------------------------------------------
REM Runs a backup with the default config ($HOME\BackupConfig.xml) — the
REM README "Quick start" flow. Args pass through, e.g.:
REM   run.cmd -ConfigPath C:\my.xml -NoMail
REM First run installs System.IO.Hashing per-user (prompts first). Restore is
REM RECONSTRUCT.bat inside the backup folder, not this file. Windows-only
REM product (PowerShell 7): the POSIX run.sh/run.command twins are not shipped.
set "RUN_CMD=pwsh -NoProfile -File FileBackup.ps1"
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

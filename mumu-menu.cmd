@echo off
rem Double-click launcher for mumu-menu.ps1.
rem Runs PowerShell with -ExecutionPolicy Bypass for THIS process only,
rem so no machine-wide security setting has to be changed.
setlocal
cd /d "%~dp0"
if not exist "%~dp0mumu-menu.ps1" (
    echo mumu-menu.ps1 not found next to this launcher.
    pause
    exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0mumu-menu.ps1"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
    echo.
    echo Menu exited with code %RC%.
    pause
)
endlocal

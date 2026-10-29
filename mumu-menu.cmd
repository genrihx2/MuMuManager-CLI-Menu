@echo off
:: mumu-menu.cmd — Windows launcher for mumu-menu.ps1
::
:: Intended entry points for both interactive use and the automation facade:
::   mumu-menu.cmd run             interactive menu (default)
::   mumu-menu.cmd run --once     one-shot menu render
::   mumu-menu.cmd start --index 1 --restore   launch + wait for boot
::   mumu-menu.cmd wait --index 1 --timeout 120
::   mumu-menu.cmd status --deep
::
:: Environment (mirrors the Go facade contract):
::   MUUMU_EXE       path to MuMuManager.exe
::   MUUMU_INDEX     default instance index
::   MUUMU_RESTORE   "1" enables --restore by default
::
:: Implementation note: this cmd wrapper exists so a future native CLI facade
:: (cmd/mumu-menu-cmd) can call the same verbs without duplicating the PS
:: invocation plumbing. Today it is a thin dispatcher; the real verbs live in
:: mumu-menu.ps1.

setlocal EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "PS_EXE="

:: Prefer pwsh when available, fall back to powershell.exe.
where pwsh >nul 2>&1 && set "PS_EXE=pwsh" || (
    where powershell >nul 2>&1 && set "PS_EXE=powershell"
)

if not defined PS_EXE (
    echo [ERROR] Neither pwsh nor powershell found on PATH.
    exit /b 2
)

set "ARGS="

:parse
if "%~1"=="" goto :run
if /i "%~1"=="/?" goto :help
if /i "%~1"=="--help" goto :help
if /i "%~1"=="-help" goto :help
set "ARGS=!ARGS! %1"
shift
goto :parse

:help
echo.
echo Usage: mumu-menu.cmd ^<verb^> [options]
echo.
echo Verbs:
echo   run            Start the interactive menu ^(default^).
echo   run --once     Render the menu once and exit 0.
echo   start [--index N] [--restore]
echo                  Launch the instance and wait for boot.
echo   wait [--index N] [--timeout s]
echo                  Poll until android_started ^(default timeout 120s^).
echo   status         Print a machine-readable instance/status tree ^(JSON^).
echo.
echo Environment:
echo   MUUMU_EXE      path to MuMuManager.exe
echo   MUUMU_INDEX    default instance index
echo   MUUMU_RESTORE  set to "1" to prefer --restore by default
echo.
goto :end

:run
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%mumu-menu.ps1" %ARGS%
goto :end

:end
endlocal

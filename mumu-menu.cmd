@echo off
:: mumu-menu.cmd - Windows launcher for mumu-menu.ps1
::
:: Double-click (or run with no arguments) starts the interactive menu.
:: Everything else is a thin dispatch onto the parameters mumu-menu.ps1
:: actually declares - the verbs map to -Action, the options map to
:: -Instance / -Lines / -TimeoutSec / -Json / -Force. No environment
:: variables are read or set here.
::
::   mumu-menu.cmd                        interactive menu
::   mumu-menu.cmd launch  [options]      start instances, wait for boot
::   mumu-menu.cmd stop    [options]      stop instances
::   mumu-menu.cmd restart [options]      stop, wait 5 s, start, wait for boot
::   mumu-menu.cmd logs    [options]      print a logcat snapshot
::   mumu-menu.cmd help                   this text
::
:: Options (valid for the four verbs above):
::   --instance <all|N|N,M>   default all      -> -Instance
::   --lines <N>              default 200      -> -Lines (logs only)
::   --timeout <seconds>      default 300      -> -TimeoutSec (launch/restart)
::   --json                   machine-readable -> -Json
::   --force                  ignore the ETag cache -> -Force
::
:: Exit codes: 0 all targets ok, 1 at least one target failed, 2 usage or
:: environment error (unknown verb/option, no PowerShell on PATH).

setlocal EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "PS_EXE="

:: Prefer pwsh when available, fall back to powershell.exe.
where pwsh >nul 2>&1 && set "PS_EXE=pwsh" || (
    where powershell >nul 2>&1 && set "PS_EXE=powershell"
)

if not defined PS_EXE (
    echo [ERROR] Neither pwsh nor powershell found on PATH.
    endlocal & exit /b 2
)

set "VERB="
set "OPT_INSTANCE="
set "OPT_LINES="
set "OPT_TIMEOUT="
set "OPT_JSON="
set "OPT_FORCE="

if "%~1"=="" goto :run
if /i "%~1"=="/?" goto :help
if /i "%~1"=="/h" goto :help
if /i "%~1"=="--help" goto :help
if /i "%~1"=="-h" goto :help
if /i "%~1"=="help" goto :help

:: A leading option (for example --force) keeps the interactive menu and
:: only applies that flag to it.
set "FIRST=%~1"
if "!FIRST:~0,2!"=="--" goto :options

if /i "%~1"=="launch"  (set "VERB=launch"  & shift & goto :options)
if /i "%~1"=="stop"    (set "VERB=stop"    & shift & goto :options)
if /i "%~1"=="restart" (set "VERB=restart" & shift & goto :options)
if /i "%~1"=="logs"    (set "VERB=logs"    & shift & goto :options)

echo [ERROR] Unknown verb "%~1".
goto :usage_error

:options
if "%~1"=="" goto :run
set "OPT=%~1"

if /i "%OPT%"=="--json" (
    set "OPT_JSON=-Json"
    shift
    goto :options
)
if /i "%OPT%"=="--force" (
    set "OPT_FORCE=-Force"
    shift
    goto :options
)
if /i "%OPT%"=="--instance" goto :value_instance
if /i "%OPT%"=="--lines" goto :value_lines
if /i "%OPT%"=="--timeout" goto :value_timeout

echo [ERROR] Unknown option "%OPT%".
goto :usage_error

:value_instance
if "%~2"=="" goto :missing_value
set "OPT_INSTANCE=%~2"
shift
shift
goto :options

:value_lines
if "%~2"=="" goto :missing_value
set "OPT_LINES=%~2"
shift
shift
goto :options

:value_timeout
if "%~2"=="" goto :missing_value
set "OPT_TIMEOUT=%~2"
shift
shift
goto :options

:missing_value
echo [ERROR] Option "%OPT%" needs a value.
goto :usage_error

:help
echo.
echo Usage: mumu-menu.cmd [verb] [options]
echo.
echo Verbs (map to mumu-menu.ps1 -Action):
echo   launch       Start the instances and wait for Android boot.
echo   stop         Stop the instances.
echo   restart      Stop, wait 5 seconds, start, wait for Android boot.
echo   logs         Print a logcat snapshot.
echo   help         Show this text.
echo   (no verb)    Interactive menu.
echo.
echo Options:
echo   --instance ^<all^|N^|N,M^>  default all        -^> -Instance
echo   --lines ^<N^>              default 200        -^> -Lines (logs)
echo   --timeout ^<seconds^>      default 300        -^> -TimeoutSec
echo   --json                   print JSON          -^> -Json
echo   --force                  ignore ETag cache  -^> -Force
echo.
echo Examples:
echo   mumu-menu.cmd
echo   mumu-menu.cmd launch --instance 0 --timeout 180
echo   mumu-menu.cmd logs --instance all --lines 50 --json
echo.
goto :end

:usage_error
echo.
echo Run "mumu-menu.cmd help" for the documented verbs and options.
endlocal & exit /b 2

:run
set "PS_ARGS=-NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%mumu-menu.ps1""
if defined VERB set PS_ARGS=!PS_ARGS! -Action !VERB!
if defined OPT_INSTANCE set PS_ARGS=!PS_ARGS! -Instance "!OPT_INSTANCE!"
if defined OPT_LINES set PS_ARGS=!PS_ARGS! -Lines !OPT_LINES!
if defined OPT_TIMEOUT set PS_ARGS=!PS_ARGS! -TimeoutSec !OPT_TIMEOUT!
if defined OPT_JSON set PS_ARGS=!PS_ARGS! -Json
if defined OPT_FORCE set PS_ARGS=!PS_ARGS! -Force
"%PS_EXE%" !PS_ARGS!
set "RC=!ERRORLEVEL!"
endlocal & exit /b %RC%

:end
endlocal

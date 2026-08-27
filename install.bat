@echo off
title MuMuManager CLI Menu Installer
echo ======================================
echo   MuMuManager CLI Menu - Installer
echo ======================================
echo.
echo This will download and run the latest version.
echo.
pause

set "INSTALL_DIR=%USERPROFILE%\MuMuManager CLI Menu"

if not exist "%INSTALL_DIR%" (
    echo Creating directory: %INSTALL_DIR%
    mkdir "%INSTALL_DIR%"
)

echo.
echo Downloading mumu-menu.ps1...
powershell -NoProfile -ExecutionPolicy Bypass -Command "& { try { Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/genrihx2/MuMuManager-CLI-Menu/main/mumu-menu.ps1' -OutFile '%INSTALL_DIR%\mumu-menu.ps1' -UseBasicParsing; Write-Host '  OK' -ForegroundColor Green } catch { Write-Host '  Failed: ' + $_.Exception.Message -ForegroundColor Red; exit 1 } }"

echo Downloading .version...
powershell -NoProfile -ExecutionPolicy Bypass -Command "& { try { Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/genrihx2/MuMuManager-CLI-Menu/main/.version' -OutFile '%INSTALL_DIR%\.version' -UseBasicParsing; Write-Host '  OK' -ForegroundColor Green } catch { Write-Host '  Failed: ' + $_.Exception.Message -ForegroundColor Red } }"

echo Downloading README.md...
powershell -NoProfile -ExecutionPolicy Bypass -Command "& { try { Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/genrihx2/MuMuManager-CLI-Menu/main/README.md' -OutFile '%INSTALL_DIR%\README.md' -UseBasicParsing; Write-Host '  OK' -ForegroundColor Green } catch { Write-Host '  Failed: ' + $_.Exception.Message -ForegroundColor Red } }"

echo Downloading SKILL.md...
powershell -NoProfile -ExecutionPolicy Bypass -Command "& { try { Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/genrihx2/MuMuManager-CLI-Menu/main/SKILL.md' -OutFile '%INSTALL_DIR%\SKILL.md' -UseBasicParsing; Write-Host '  OK' -ForegroundColor Green } catch { Write-Host '  Failed: ' + $_.Exception.Message -ForegroundColor Red } }"

echo.
echo ======================================
echo   Installation complete!
echo ======================================
echo.
echo Installed to: %INSTALL_DIR%
echo.
echo To run: cd "%INSTALL_DIR%" && mumu-menu.ps1
echo Or add to PATH: setx PATH "%PATH%;%INSTALL_DIR%"
echo.
echo Starting MuMuManager CLI Menu...
echo.
cd "%INSTALL_DIR%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%INSTALL_DIR%\mumu-menu.ps1"
pause

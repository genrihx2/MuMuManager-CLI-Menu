# Sysdig vulnerability scan target
# PowerShell-based project — uses pwsh base image for SARIF scan.
# This image is NOT for running the tool (MuMuManager.exe requires Windows).

FROM mcr.microsoft.com/powershell:lts-7.4-bookworm-slim

LABEL maintainer="genrihx2"
LABEL description="MuMuManager CLI Menu — PowerShell interactive menu for Netease MuMu Emulator"

WORKDIR /app

# Copy project files
COPY mumu-menu.ps1 .
COPY bootstrap-update.ps1 .
COPY SKILL.md .
COPY README.md .
COPY .version .

# Default: launch the interactive menu
ENTRYPOINT ["pwsh", "-NoProfile", "-File", "/app/mumu-menu.ps1"]

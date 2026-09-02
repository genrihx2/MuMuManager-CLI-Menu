---
name: mumu-manager-cli
description: Interactive PowerShell menu for managing MuMu Emulator instances via MuMuManager.exe. Features: instance control, app management, device spoofing, SIM operator change, auto-update, code signing.
---

# MuMuManager CLI Menu

## Purpose
Interactive PowerShell menu for managing your own MuMu Emulator instances locally.
All operations run locally through the official `MuMuManager.exe`.

## Project Structure
```
mumu-menu.ps1          # Main script (v1.1.0)
README.md              # Documentation with changelog
SKILL.md               # This file
.gitattributes         # Line ending normalization (LF)
.github/workflows/
  release.yml          # Auto-release on version bump
  sync-readme.yml      # Sync README with script menu
  sync-version.yml     # Sync .version from script
  security-scan.yml    # PSScriptAnalyzer → SARIF
```

## Requirements
- Windows 10/11
- PowerShell 5.1+
- MuMu Emulator 6.x (minimum v4.0.0.3179)
- `MuMuManager.exe` at: `C:\Program Files\Netease\MuMuPlayer\nx_main\MuMuManager.exe`

## Installation
```powershell
# Quick run (one command):
irm https://raw.githubusercontent.com/genrihx2/MuMuManager-CLI-Menu/main/mumu-menu.ps1 -OutFile $env:TEMP\mumu-menu.ps1; & $env:TEMP\mumu-menu.ps1

# Or git clone:
git clone https://github.com/genrihx2/MuMuManager-CLI-Menu.git
cd MuMuManager-CLI-Menu
.\mumu-menu.ps1
```

## Menu Commands
- `[1]` Show instance info
- `[2-5]` Launch/Shutdown/Restart/Create emulator
- `[6-9]` Apps/Settings/Install APK/Uninstall
- `[DI]` Random device IDs (IMEI/Android ID/MAC)
- `[DM]` Spoof device model (brand/model/certification)
- `[SIM]` Change SIM operator (MCC/MNC) — 38 presets + custom
- `[U]` Check for updates (downloads from GitHub Releases)
- `[V]` Version info (script, MuMu, .NET, disk, ADB, certificate)
- `[K]` Update GitHub token (DPAPI-encrypted)
- `[CRT]` Certificate manager (self-signed code signing)
- `[Z]` Security test

## Workflows
### Release (auto)
- Triggers on push to `main` when `mumu-menu.ps1` changes
- Reads version from `$scriptVer` variable
- Creates ZIP (mumu-menu.ps1, README.md, SKILL.md, .version)
- SHA256 checksum + ZIP integrity verification
- Generates release notes with changelog, commit list, install instructions

### Sync README
- Triggers on push to `main` when `mumu-menu.ps1` changes
- Runs `update-readme.ps1` to sync menu block in README.md
- Auto-commits if changed

### Sync .version
- Triggers on push to `main` when `mumu-menu.ps1` changes
- Reads `$scriptVer` from script, writes to `.version`
- Auto-commits if changed

### Security Scan
- PSScriptAnalyzer with custom settings
- SARIF output for GitHub code scanning
- Summary table (errors/warnings)

## Versioning
- Version is stored in `$scriptVer` variable in `mumu-menu.ps1`
- `.version` file is synced automatically by workflow
- To create a release: bump `$scriptVer`, commit, push
- Tags follow `vX.Y.Z` format

## Security
- Device spoofing is DUAL-USE: privacy/testing on YOUR OWN instances only
- Token stored DPAPI-encrypted (`.github-token.dpapi`)
- Update downloads TEXT files only (.ps1/.md) from tagged GitHub Releases
- SHA256 verification for all downloads
- Code signing via self-signed certificate (created via `[CRT]`)
- See SECURITY.md for full details

## Troubleshooting
- MuMu not found: edit `$MumuPath` at top of `mumu-menu.ps1`
- Version mismatch: run `[V]` to check script vs MuMu version
- Update fails: run `[K]` to configure GitHub token
- Certificate expired: run `[CRT]` → `[1]` to recreate

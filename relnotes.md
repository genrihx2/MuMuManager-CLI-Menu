# MuMuManager CLI Menu

Interactive PowerShell menu for managing MuMu Emulator instances through the official `MuMuManager.exe`.

This file contains a cleaner release history for the project, focusing on the most important updates and major milestones.

---

## Latest release

### v1.22.65 (12.10.2026)
- Fixed a hang in the live `[G] adb logcat` view.
- The live logcat branch was assigning the output pipeline before iteration, which blocked PowerShell until the process ended.
- Synchronized version markers in `mumu-menu.ps1`, `relnotes.md`, `README.md`, and `.version`.

**EN summary:** Fixed the live `adb logcat` hang in `[G]`. The live branch assigned the pipeline before consuming it, which caused PowerShell to block until the process exited. Version markers were synchronized across the project.

---

## Recent highlights

### v1.22.64 (11.10.2026)
- Restored the `[3] adb logcat — live` entry in the Logs menu.
- Fixed a formatting issue where two menu lines were accidentally merged into one.

### v1.22.63 (11.10.2026)
- Fixed `adb` invocation syntax through MuMuManager.
- Live logcat stops cleanly when leaving the view.
- Updated PSScriptAnalyzer settings for repository style consistency.

### v1.22.62 (09.10.2026)
- Added readonly diagnostics for orphaned MuMu instance folders.
- Improved live logcat exit handling.

### v1.22.61 (06.10.2026)
- Added a quick-switch path in `[DIAG]` for installs with a running MuMu instance.
- Fixed a false warning in diagnostics related to script version detection.

### v1.22.60 (06.10.2026)
- Added a multi-install drift report for machines with side-by-side MuMu installations.
- Improved diagnostics for install mismatch detection and active-install awareness.

### v1.22.59 (06.10.2026)
- Added multi-install detection and active installation selection.
- Fixed instance selection so a healthy live instance is preferred over stale folders.

### v1.22.58 (05.10.2026)
- Added Resource Monitor v2 with pause, session peaks, sparkline, exports, and RAM delta tracking.

### v1.22.57 (05.10.2026)
- Added `[CMP] Compare instance settings`.
- Improved resource monitor instance mapping via `MuMuManager info -v all`.

### v1.22.56 (05.10.2026)
- Added `[RM] Resource monitor (CPU/RAM, live)`.
- Documented additional Sigma/YARA exclusions and updated security notes.

### v1.22.55 (02.10.2026)
- Added a verified false-positive section to `SECURITY.md`.
- Softened AV heuristic language in the docs without changing functionality.
- Updated workflow permissions and CI security behavior.

---

## Earlier major releases

### v1.22.54 (30.09.2026)
- Improved tunnel owner detection in `Test-MumuTunnelAB`.

### v1.22.53 (29.09.2026)
- Startup/version output now shows only the active MuMu installation.

### v1.22.52 (29.09.2026)
- Fixed strict `pwsh` startup issues.
- Restricted EXE-version reporting to the active MuMu installation.

### v1.22.51 (29.09.2026)
- Added automatic detection of MuMu install roots on any drive.
- Improved version reporting with real full paths.

### v1.22.50 (29.09.2026)
- Added automatic MuMu EXE version display at startup.

### v1.22.49 (29.09.2026)
- Added a Mark-of-the-Web troubleshooting section in the README.
- Hardened release ZIP validation logic.

### v1.22.48 (28.09.2026)
- Restored a complete self-update package.
- Added `[WN] Watch MuMu network + updater` diagnostics screen.

### v1.22.47 (27.09.2026)
- Version sync release; no functional script changes.

### v1.22.46 (27.09.2026)
- Added the diagnostics trio to the release ZIP.
- Updated the release file-set contract to 8 files.

### v1.22.45 (26.09.2026)
- Added deployed-layout CI coverage.
- Improved release gate audit checks and Pester matrix validation.

### v1.22.44 (25.09.2026)
- Fixed a persisted rejected GitHub token issue.

### v1.22.43 (25.09.2026)
- Made the release gate self-sufficient.
- Added weekly ZIP verification in the release guard workflow.

### v1.22.42 (25.09.2026)
- Added a Pester CI matrix for both PowerShell 5.1 and pwsh 7.
- Fixed `Get-ReleaseInfo.PublishedAt` compatibility across runtimes.

### v1.22.41 (25.09.2026)
- Fixed dead `Get-ReleaseInfo` headers and clearer update failure handling.

### v1.22.40 (24.09.2026)
- Added `Get-ReleaseInfo` helpers for structured release metadata.
- Reworked GitHub release fetch logic around the new helper.

### v1.22.39 (22.09.2026)
- Improved log stack collapsing in `[G] View logs`.
- Corrected release-date documentation in README and relnotes.

### v1.22.38 (22.09.2026)
- Fixed `Write-Debug` usage in emulator creation.

### v1.22.37 (22.09.2026)
- Redesigned the instance creation screen.

### v1.22.36 (21.09.2026)
- Added case-insensitive search in log view.

### v1.22.35 (21.09.2026)
- Switched log snapshot default to errors-only when empty input is entered.

### v1.22.34 (21.09.2026)
- Added quiet-mode log filtering to reduce known noisy entries.

### v1.22.33 (21.09.2026)
- Redesigned shutdown and restart screens with clearer guards and final status.

### v1.22.32 (21.09.2026)
- Redesigned log viewer with state indication and colorized log levels.

### v1.22.31 (21.09.2026)
- Redesigned launch flow with better status reporting and guards.

### v1.22.30 (21.09.2026)
- Added DevSkim security linting.
- Updated project documentation and menu coverage.

### v1.22.29 (21.09.2026)
- Fixed `[TN]` tag extraction logic.

### v1.22.28 (21.09.2026)
- Added CDN mirror freshness checks.
- Added `cdn-sync` automation for jsDelivr mirror updates.

### v1.22.27 (21.09.2026)
- Added SmartScreen and Mark-of-the-Web guidance for browser-extracted ZIP files.

### v1.22.26 (21.09.2026)
- Improved stale-failure handling in diagnostics.

### v1.22.25 (21.09.2026)
- Fixed false drift warnings on re-signed installs.

### v1.22.24 (21.09.2026)
- Stabilized release tagging and tag-backed fixes after recent mainline changes.

### v1.22.23 (20.09.2026)
- Added `[FPS]` frame-rate presets and overview.
- Improved `[RT]` UI and `[VE]` validation behavior.

### v1.22.22 (20.09.2026)
- Added network speed tests and better update retries.

### v1.22.21 (18.09.2026)
- Added auto-resigning after update when a valid certificate is available.

### v1.22.20 (18.09.2026)
- Fixed virtual environment validation logic.

### v1.22.19 (18.09.2026)
- Added `[VE]` Virtual Environment support.

### v1.22.18 (18.09.2026)
- Fixed root toggle validation and state-read consistency.

### v1.22.17 (18.09.2026)
- Added `[RT]` root toggle support for individual instances.

### v1.22.16 (18.09.2026)
- Fixed BOM handling and UTF-8 output for `.version` and update scripts.

### v1.22.15 (18.09.2026)
- Added jsDelivr fallback for update downloads.

### v1.22.14 (17.09.2026)
- Corrected YAML frontmatter escaping in `SKILL.md`.

### v1.22.13 (17.09.2026)
- Hardened update pinning to immutable commit SHAs.

### v1.22.12 (17.09.2026)
- Removed stale `bootstrap-update.ps1.old` leftovers after updater refresh.

### v1.22.11 (17.09.2026)
- Removed BOM from README and SKILL.md and hardened the writer logic.

### v1.22.10 (17.09.2026)
- Added repair option for missing `.ps1` BOM files in `[UW]`.

### v1.22.9 (17.09.2026)
- Improved BOM diagnostics and safety checks for fix mode.

### v1.22.8 (17.09.2026)
- Added `[UP] Update plan (dry-run)`.

### v1.22.7 (17.09.2026)
- Added `bootstrap-update.ps1 -WhatIf` dry-run support.

### v1.22.6 (16.09.2026)
- Improved diagnostics to separate info-only findings from real problems.

### v1.22.5 (16.09.2026)
- Fixed false `ADB bridge not ready` warnings on healthy installations.

### v1.22.4 (16.09.2026)
- Hardened curl usage and removed string-based `cmd /c` wrappers.

### v1.22.3 (16.09.2026)
- Fixed valid GitHub token checks reporting as invalid.

### v1.22.2 (16.09.2026)
- Improved honest rate-limit reporting and update verification behavior.

### v1.22.1 (16.09.2026)
- Fixed ETag cache population issues.

### v1.22.0 (16.09.2026)
- Added persistent ETag cache and cache-aware status output.

### v1.21.x and earlier
- Added journal export, single-flight update locking, deep integrity verification, README recovery guidance, and many diagnostics and security improvements.

---

## Notes

- Full historical details are available in the project GitHub releases and in `README.md`.
- This file is intentionally kept concise and easy to scan for the most relevant release information.

**Requirements:** Windows 10/11 · PowerShell 5.1+ · MuMu Emulator 6.x

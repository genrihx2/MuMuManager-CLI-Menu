# MuMuManager CLI Menu

Interactive PowerShell menu for managing MuMu Emulator instances through the official `MuMuManager.exe`.

This file contains a concise release history for the project. For full commit-level detail, see the GitHub releases and commit history.

---

## v1.22.65 (12.10.2026)

- Fixed a hang in the live `[G] adb logcat` view.
- The live logcat branch was assigning the output pipeline before iteration, which blocked PowerShell until the process ended.
- Synchronized version markers in `mumu-menu.ps1`, `relnotes.md`, `README.md`, and `.version`.

**EN summary:** Fixed the live `adb logcat` hang in `[G]`. The live branch assigned the pipeline before consuming it, which caused PowerShell to block until the process exited. Version markers were synchronized across the project.

---

## Release

- Major release: semantic-version bump to `v10.0.0` to mark a stable, production-ready milestone and unify public-facing versioning.
- Documentation and release notes reorganized for clarity (relnotes.md and README.md).
- No behavioral changes to the runtime scripts in this commit — this release primarily records the versioning milestone and documentation cleanups.
- If you plan to publish a GitHub Release for `v10.0.0`, create a signed tag and attach the official release ZIP (release automation will run CI checks and VirusTotal scans).

**Notes for maintainers:**
- Consider bumping `$scriptVer` in `mumu-menu.ps1` and `.version` to `10.0.0` at release time if you want parity between the tag and the script marker.
- This relnote is intentionally succinct; the detailed per-version history is preserved below under "Recent highlights" and in the GitHub Releases.

---

## Latest release

### Details
- Fixed a hang in the live `[G] adb logcat` view.
- The live logcat branch was assigning the output pipeline before iteration, which blocked PowerShell until the process ended.
- Synchronized version markers in `mumu-menu.ps1`, `relnotes.md`, `README.md`, and `.version`.

**EN summary:** Fixed the live `adb logcat` hang in `[G]`. The live branch assigned the pipeline before consuming it, which caused PowerShell to block until the process exited. Version markers were synchronized across the project.

---

## Recent highlights

### Release note
- Restored the `[3] adb logcat — live` entry in the Logs menu.
- Fixed a formatting issue where two menu lines were accidentally merged into one.

### Release note
- Fixed `adb` invocation syntax through MuMuManager.
- Live logcat stops cleanly when leaving the view.
- Updated PSScriptAnalyzer settings for repository style consistency.

### Release note
- Added readonly diagnostics for orphaned MuMu instance folders.
- Improved live logcat exit handling.

### Release note
- Added a quick-switch path in `[DIAG]` for installs with a running MuMu instance.
- Fixed a false warning in diagnostics related to script version detection.

### Release note
- Added a multi-install drift report for machines with side-by-side MuMu installations.
- Improved diagnostics for install mismatch detection and active-install awareness.

---

## Earlier major releases

(See full history in GitHub Releases and README)

---

## Notes

- This relnotes file is intentionally concise and focuses on the most relevant milestones.
- For full historical detail, consult GitHub Releases and the commit history.

**Requirements:** Windows 10/11 · PowerShell 5.1+ · MuMu Emulator 6.x

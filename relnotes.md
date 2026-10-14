# MuMuManager CLI Menu

Interactive PowerShell menu for managing MuMu Emulator instances through the official `MuMuManager.exe`.

This file contains the release note for the v10.0.0 milestone. All previous per-version blocks have been removed; only the v10.0.0 entry is kept as requested.

---

## v10.0.0 (2026-10-14)

- Major release: semantic-version bump to `v10.0.0` to mark a stable, production-ready milestone and unify public-facing versioning.
- Documentation and release notes reorganized for clarity (relnotes.md and README.md).
- No behavioral changes to the runtime scripts in this commit — this release primarily records the versioning milestone and documentation cleanups.
- If you plan to publish a GitHub Release for `v10.0.0`, create a signed tag and attach the official release ZIP (release automation will run CI checks and VirusTotal scans).

**Notes for maintainers:**
- Consider bumping `$scriptVer` in `mumu-menu.ps1` and `.version` to `10.0.0` (no leading `v`) so the changelog-sync workflow sees consistency.

---

## Notes

- Full historical details are preserved in the Git commit history and GitHub releases if needed.

**Requirements:** Windows 10/11 · PowerShell 5.1+ · MuMu Emulator 6.x

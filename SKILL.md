---
name: mumu-manager-cli
description: "Interactive PowerShell menu for managing MuMu Emulator instances via MuMuManager.exe. Features: instance control, app management, device spoofing, SIM operator change, virtual environments, FPS control, auto-update with integrity verification, code signing, VirusTotal integration."
---

# MuMuManager CLI Menu

## Purpose
Interactive PowerShell menu for managing your own MuMu Emulator instances locally.
All operations run locally through the official `MuMuManager.exe`.

## Project Structure
```
mumu-menu.ps1           # Main script (version lives in $scriptVer, ~line 238)
bootstrap-update.ps1    # Standalone updater/recovery path (ships inside every release ZIP)
update-readme.ps1       # Regenerates the menu block in README.md
README.md               # Documentation + changelog (what's-new + version table)
relnotes.md             # Release notes (top section must match .version / $scriptVer)
SECURITY.md             # Security policy, threat model, endpoint table, Sigma FP analysis
RELEASE-RUNBOOK.md      # Release pipeline runbook + Release guard + CDN sync docs
ISSUE-DRAFT.md          # Historical roadmap / issue draft
.version                # Version marker synced by CI (BOM-less, e.g. v1.22.29)
tests/
  mumu-menu.Tests.ps1   # Pester suite (150+ tests; the repo-file-dependent test is tagged RepoFiles)
  run-pester.ps1        # Test runner
  test-bootstrap-update.ps1
  test-changelog-sync.ps1  # relnotes = .version = scriptVer + README table sync
  test-deployed-layout.ps1 # Repo-vs-install drift guard: suite inside a fixture with ONLY the deployed files, both engines, RepoFiles excluded
PSScriptAnalyzerSettings.psd1
.github/workflows/
  release.yml           # Tag-driven release; on main push derives tag from $scriptVer
  tests.yml             # Pester matrix: PS 5.1 + pwsh on pinned Pester 5.7.1, plus a preinstalled-Pester canary, plus a deployed-layout fixture leg (.github/actions/pester-unit)
  lint.yml              # actionlint for workflow files
  changelog-check.yml   # README/relnotes/.version consistency gate
  sync-readme.yml       # Auto-sync README menu block after script changes
  sync-version.yml      # Auto-sync .version from $scriptVer
  security-scan.yml     # PSScriptAnalyzer -> SARIF -> code scanning
  virustotal.yml        # Post-release VT scan, appends verdicts to the release body
  release-guard.yml     # Weekly release audit (assets + VT verdicts + .version match)
  cdn-sync.yml          # Purges the jsDelivr @main mirror cache on push / weekly / manual
```

## Requirements
- Windows 10/11
- PowerShell 5.1+
- MuMu Emulator 6.x (minimum v4.0.0.3179)
- `MuMuManager.exe` at: `C:\Program Files\Netease\MuMuPlayer\nx_main\MuMuManager.exe`
- Optional: GitHub token (menu `[K]`) for higher API rate limits; VirusTotal API key (menu `[VK]`)

## Installation
```powershell
# Quick run (one command):
irm https://raw.githubusercontent.com/genrihx2/MuMuManager-CLI-Menu/main/mumu-menu.ps1 -OutFile $env:TEMP\mumu-menu.ps1; & $env:TEMP\mumu-menu.ps1

# Or git clone:
git clone https://github.com/genrihx2/MuMuManager-CLI-Menu.git
cd MuMuManager-CLI-Menu
.\mumu-menu.ps1

# Or bootstrap into an existing folder (also the recovery path):
.\bootstrap-update.ps1 <target-dir>
```

## Menu Commands
### Instances
- `[1]` Show emulator info — `[2-5]` Launch / Shutdown / Restart / Create
- `[C]` Clone — `[X]` Delete — `[N]` Rename

### Apps and settings
- `[6]` List installed apps — `[7]` Show settings
- `[RT]` Enable / disable root (instance) — `[VE]` Virtual environment (enable/disable/remove)
- `[FPS]` Set frame rate (30/60/90/120/144/240/uncapped, per-instance overview)
- `[8]` Install APK — `[9]` Uninstall app — `[G]` View logs

### Batch
- `[B]` Launch all — `[D]` Shutdown all — `[R]` Restart all — `[I]` Install APK to all

### Window
- `[W]` Show all windows — `[H]` Hide all — `[L]` Layout windows

### Tools / ADB
- `[S]` Screenshot — `[A]` ADB command — `[AF]` ADB file transfer — `[AS]` ADB screen capture — `[AH]` ADB interactive shell
- `[O]` Clear app data — `[P]` Force stop app — `[T]` Start app
- `[E]` Export data — `[BA]` Backup instance — `[RE]` Restore — `[RB]` Rollback from backup

### Keys / certificates
- `[K]` Update GitHub token (DPAPI-encrypted, or `[E]` ephemeral session-only)
- `[VK]` Set VirusTotal API key — `[CRT]` Create/sign certificate (auto re-sign after updates)

### Tests
- `[TC]` Connection test — `[TN]` Network test (guest probes + host-side CDN mirror freshness)
- `[TS]` Network speed test — `[TD]` Dependencies test
- `[VT]` VirusTotal scan — `[VF]` VirusTotal upload file — `[UW]` Fix Unicode / encoding (BOM repair)

### Spoofing (dual-use, own instances only)
- `[DM]` Spoof device model — `[SIM]` SIM operator / country (MCC/MNC) — `[SIM+]` View/clear auto-apply SIM config
- `[SC]` SIM check — `[AI]` Set Android ID — `[DI]` Random device IDs

### Info / updates / diagnostics
- `[V]` Version info — `[U]` Check for updates — `[UP]` Update plan (dry-run)
- `[F]` Verify installation (files vs release tag, signature-block aware hashing)
- `[ST]` Install status (read-only) — `[J]` Update journal — `[DIAG]` Problem diagnostics
- `[DL]` Download repository — `[CR]` Create release — `[FR]` Fix release encoding

## Workflows
### Release (auto)
- Triggers on push of a `v*` tag, or push to `main` when `mumu-menu.ps1` changes (tag derived from `$scriptVer` and created if missing)
- Builds ZIP strictly from the tag content; fails if `$scriptVer` does not match the tag version
- ZIP contains `mumu-menu.ps1`, `README.md`, `SKILL.md`, `.version` + `.sha256` sidecar
- Release body embeds the changelog; the virustotal workflow appends per-file VT verdicts

### Sync README / Sync .version
- Trigger on push to `main` when `mumu-menu.ps1` changes
- `sync-readme` regenerates the menu block in README.md; `sync-version` writes `$scriptVer` to `.version`
- Both auto-commit if changed

### Tests / lint / changelog
- `tests.yml`: Pester matrix (PS 5.1 + pwsh on pinned Pester 5.7.1, plus a preinstalled-Pester
  canary, plus a deployed-layout leg that runs the suite inside a fixture holding only the
  deployed file set - catches tests that silently need repo-only files, which would otherwise
  surface as a red run on a healthy live install) on push/PR and weekly (Monday 08:00 UTC - the
  canary tracks the runner image, which changes independently of this repo); `lint.yml`:
  actionlint; `changelog-check.yml`: gates on `relnotes.md` top section = `.version` =
  `$scriptVer` and README what's-new/table consistency
- Local replay of the full CI matrix: `tests/run-matrix.ps1` (`-Quick` skips the canary leg;
  the deployed-layout leg runs via `tests/test-deployed-layout.ps1`)

### Security scan
- PSScriptAnalyzer with custom settings, SARIF output for GitHub code scanning

### Release guard (weekly)
- Audits every release newer than v1.18.6: canonical asset set (ZIP + .sha256), VT verdicts
  in the body, and repo `.version` == latest release tag; opens an issue on drift

### CDN sync
- Purges the jsDelivr `@main` mirror cache on every push to main (5 files), weekly
  self-heal, and manual dispatch — the update transport itself is SHA-pinned and immune

## Versioning
- Version is stored in `$scriptVer` in `mumu-menu.ps1`; `.version` is synced by CI (keep both + relnotes top section equal)
- To create a release: bump `$scriptVer` + `.version` + changelog entries, commit, push
- Tags follow `vX.Y.Z`; installations verify themselves against the tag via `[F]`

## Security
- Device spoofing is DUAL-USE: privacy/testing on YOUR OWN instances only
- GitHub token stored DPAPI-encrypted (`.github-token.dpapi`) or session-only (`[K]` -> `[E]`, never written to disk)
- Update transport: api.github.com contents API pinned to the exact commit SHA; one fallback
  fetch through the cdn.jsdelivr.net mirror of the same pinned commit; every file hash-verified
- Code signing via self-signed certificate (`[CRT]`); bootstrap re-signs `mumu-menu.ps1` after each update
- Browser SmartScreen warnings on `.ps1` downloads are extension triggers; unblock MOTW via
  `Unblock-File` or file Properties (see README SmartScreen section)
- See SECURITY.md for the full policy, endpoint table, threat model and false-positive appeal guide

## Troubleshooting
- MuMu not found: edit `$MumuPath` at top of `mumu-menu.ps1`
- Version mismatch: run `[V]`; installation integrity: run `[F]`
- Update fails (rate limit): run `[K]` to set a GitHub token; history: `[J]`
- Something broke after an update: `[RB]` rollback, or re-run `bootstrap-update.ps1`
- Health overview: `[DIAG]` (stale journal fails are classified as historical info)
- Certificate expired: run `[CRT]` -> `[1]` to recreate

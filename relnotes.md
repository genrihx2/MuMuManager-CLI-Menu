# MuMuManager CLI Menu

Interactive PowerShell menu for managing MuMu Emulator instances through the official `MuMuManager.exe`.

This file contains the release notes for the v10.3.4, v10.3.3, v10.3.1, v10.3.0, v10.2.0, v10.1.0 and v10.0.0 milestones. Older per-version blocks have been removed; only the latest entries are kept as requested.

---

## v10.3.4 (2026-10-22)

- Fix: `[V]` no longer reports a wrong OS on Windows 11. `[Environment]::OSVersion` returns `10.0` on every Windows 10/11 and an in-place upgrade leaves `ProductName` at "Windows 10 Pro", so the menu printed `OS: Windows 10.0 (Build 26300)` on an actual Windows 11 26H2 machine. The marketing name is now derived from the build number (Windows 11 starts at 22000) plus the feature-update label from the registry (`DisplayVersion`, `ReleaseId` on pre-2004 builds): `OS: Windows 11 26H2 (Build 26300)`.
- Fix (CI): a release published with `GITHUB_TOKEN` (the fallback when `RELEASE_PAT` is absent) now always gets its VirusTotal scan. GitHub does not emit `release: published` for releases created with `GITHUB_TOKEN` - that is why v10.3.3 shipped with no verdict section in its release body. The Release workflow now dispatches `virustotal.yml` explicitly with the same tag (the step is non-fatal: a dispatch failure never fails an already-published release); the `RELEASE_PAT` path is unchanged.
- Docs: SECURITY.md - the "Current for" header was pulled from v1.22.64 to v10.3.4, RU/EN entries added for the new VT fallback, CI test counter refreshed (173 -> 281).
- Tests: suite 281 passed / 0 failed, PSScriptAnalyzer 0 findings.

- Fix: Ctrl+C no longer kills the menu. The `CancelKeyPress` guard was a PowerShell ScriptBlock, and .NET raises that event on its own signal thread (`PosixSignalRegistration` on PowerShell 7) where no runspace is attached, so the delegate threw `PSInvalidOperationException` inside `GetContextFromTLS` *before* its body ran - the host died with "Unhandled exception ... Process will be terminated" instead of ignoring the key. The handler is now a compiled delegate that only flips `e.Cancel`, so it needs no runspace; when compilation is unavailable (ConstrainedLanguage) the guard is skipped instead of crashing the process, and the detach in the main loop's `finally` is guarded the same way.
- New: `mumu-menu.cmd` - double-click launcher for git clones. It starts PowerShell with `-ExecutionPolicy Bypass` for that process only, so a machine whose execution policy is `Restricted` can open the menu without changing a system security setting; it refuses to start when `mumu-menu.ps1` is not beside it. Repo-only on purpose: the deployed file set stays at nine files, so ZIP installs and installs updated through `[U]` cannot drift apart.
- Tests: a regression test invokes the real handler from a thread with no runspace (the exact failing condition) and fails on the previous script; suite: 280 passed / 0 failed / 1 skipped on both Windows PowerShell 5.1 and pwsh 7.6.7 with Pester 5.7.1.

## v10.3.1 (2026-10-19)

- Fix: the update check no longer trusts the `.version` marker alone. A release can ADD a file, and v10.3.0 added `mumu-menu.cjs`; installs that were already carrying the 10.3.0 marker (the first `[U]` run updated the menu but not the new file) were told "Up to date" and the file never arrived - reproduced live in an installed folder. Both the menu updater (`[U]`/`[UP]`) and `bootstrap-update.ps1` now scan the declared file set before the up-to-date short-circuit, report the missing names and fall through to a normal hash-verified download (`repair of <tag> (file set incomplete: ...)` in the dry-run plan). Unchanged files are still skipped by the per-file hash gate, so the repair costs only the missing bytes.
- Tests: a Pester test pins the `Update-FromGitHub` gate (same `$files` list for scan and download) and the bootstrap regression suite pins the gate position before the `Up to date` exit and the repair wording.

---

## v10.3.0 (2026-10-19)

- New: full JavaScript engine for the menu entry point. `node mumu-menu.cjs` is no longer a thin PowerShell wrapper: it discovers `MuMuManager.exe` itself (including the `.mumu-install` pin written by `[IN]`), implements `--status` / `--list` / `--status --json`, `--start <N>` / `--stop <N>` / `--restart <N>`, `--watch` (network + updater, read-only) and `--ps` (hand over to the complete PowerShell menu), plus an interactive JS menu with the same core actions. Zero npm dependencies, resolves its own folder so it works from any working directory, and is now part of the deployed file set (release ZIP, `[U]`, `[ST]`, `[F]`, rollback), so `node mumu-menu.cjs` works in an installed layout too. The PowerShell menu stays fully supported and is still the reference implementation for everything the JS engine does not implement natively.
- Fix: `[WN]` (network + updater watcher) no longer sits silent between `Session started` and `Stopped`. Root cause measured live: `Get-NetTCPConnection` is a CIM call that returned 39k rows in **52 s**, so the 5 s loop could not finish a single tick and never wrote a line. The watcher now snapshots the TCP table with `netstat -ano -p tcp` (~0.6 s for 23k rows) and matches the PID column with one regex, so a tick is ~0.7-0.9 s.
- Fix: `[WN]` reports what it sees. It logs connections that are already open at session start as `SEEN` (a long-running emulator used to look like “nothing happens”), every new 5-tuple as `NEW`, and a `HEARTBEAT` line immediately plus every 60 s with MuMu process count, updater count, external row count and tick duration.
- CI: `PSScriptAnalyzerSettings.psd1` now enables `PSUseCompatibleSyntax` with a `5.1` target. The rule is opt-in and reports `Error`, so 7-only syntax (ternary, `??`, `??=`, pipeline chains) fails `security-scan` instead of becoming a parse error on a PowerShell 5.1 install. The repo has 0 findings at introduction; a `RepoFiles`-tagged Pester test pins the rule, the surviving `ExcludeRules` and the workflow's `settings:` wiring, and a probe with ternary/`??` confirms the gate actually fires.
- Fix: a failing tick is written to the log as `ERROR | ...` and the loop continues, instead of bubbling into the menu-level `trap` (which printed a menu error and skipped the rest of the tick forever). Updater EXE metadata now uses `Get-Process` with a 60 s per-PID cache; CIM is only the fallback for protected processes. The log folder falls back to `%TEMP%` when it cannot be created.

---

## v10.2.0 (2026-10-18)

- New: menu item `[OI]` — offline installer listing (all platforms). Resolves the current official MuMu Player offline installers from the release-notes page (`mumuplayer.com/update`) and the telemetry-free CDN alias (`a11.gdl.easebar.com`), and prints every variant the project still ships: Windows offline installer (.exe, global channel), macOS disk image (.dmg), and the root-level Android ARM64 APK. The listing shows the exact filename, size, and an integrity badge (SHA-256 / length from HTTP headers) when the CDN exposes it, and never downloads anything. It also surfaces the long-term CN offline-installer signing archive (`down.mumuplayer.com`) with known-good older Windows build paths, so a specific version can be pinned or rolled back without touching the updater.
- Doc: README describes `[OI]`; `.version` and `scriptVer` bumped to `10.2.0`.
- Exit-code hygiene: the script now ends with an explicit `exit 0`, so terminal wrappers and launchers always observe a clean code on every non-error path.
- Fix: bootstrap-update.ps1 no longer redirects native stderr (`2>$null`). Under Windows PowerShell 5.1 with `$ErrorActionPreference='Stop'` a redirected
  native stderr is marshaled as a terminating error, so the first curl error line (e.g. `curl: (22) ... returned error: 401`) killed the whole update run.
- Fix: a rejected GitHub token is now actually detected. `--fail` suppresses the HTTP-error body, so the old `"Bad credentials"` body check could never
  see a real 401 (curl exits 22 with no output). Both GitHub-API helpers now retry the same URL once without auth; if anonymous succeeds, the token is
  disabled for the run with a re-save hint. Regression tests T3b (live 401 fallback) and T3c (no `2>$null` anywhere) pin the behavior.
- New: menu `[F]` auto-repairs the installation. When the integrity check reports DRIFT/MISSING files, it now offers to restore exactly those files
  from the pinned release commit: backup first, SHA-256-verified bytes, file-set whitelist, JSON-metadata guard, journaled as `repair-ok`/`repair-fail`.
  The running script is staged as `mumu-menu.ps1.new` and applied at the next menu start (same contract as `[U]`). A Pester Describe pins the
  lock/backup/hash/whitelist invariants.
- Fix: the release page's verification snippet now actually works on Windows PowerShell 5.1. It called bare `curl`, which 5.1 aliases to
  `Invoke-WebRequest` - that rejects `-sL`/`-o` with a parameter-binding error, so the `.sha256` sidecar was never downloaded. The generator
  (`.github/workflows/release.yml`) now emits `curl.exe`, downloads both the ZIP and the sidecar, and performs the comparison itself
  (sidecar first token vs lowercased `Get-FileHash`): the old "compare by eye" instruction could never match literally, since `Get-FileHash`
  prints UPPERCASE and the sidecar holds a lowercase hash plus the filename. Verified live on both engines against the v10.1.0 assets
  (`SHA256 OK` on the pristine ZIP, `SHA256 MISMATCH` with both hashes after a one-byte tamper); a RepoFiles-tagged Pester test pins the
  generator form so the snippet cannot silently regress.

---


## v10.1.0 (2026-10-17)

- New: menu item `[MU]` — read-only MuMu emulator update check. Compares the installed version (`MuMuManager.exe version`) with the newest entry on the official release-notes page (`mumuplayer.com/update`), prints a verdict (update available / up to date / ahead-of-public-channel / cannot check) and never downloads or installs anything — emulator upgrades go through NetEase's built-in MuMu updater.
- Hardened: the menu window no longer dies on accidental input. Ctrl+C inside the menu is ignored (exit with `0`/`q`; closing the window still works), a script-level `trap` returns runtime errors to the menu instead of ending the script, and a redirected/piped stdin exits the menu cleanly instead of hanging on "Press any key". The Ctrl+C guard is released on every exit path, so an enclosing interactive shell keeps normal Ctrl+C behaviour.
- Housekeeping: `.coderabbit.yaml` rewritten against the published CodeRabbit schema (`https://coderabbit.ai/integrations/schema.v2.json`) — the previous revision used keys that do not exist in the schema and was silently ignored in favor of UI settings/defaults.
- Pester suite: 261/261 passed.

---

## v10.0.0 (2026-10-14)

- Major release: semantic-version bump to `v10.0.0` to mark a stable, production-ready milestone and unify public-facing versioning.
- Documentation and release notes reorganized for clarity (relnotes.md and README.md).
- No behavioral changes to the runtime scripts in this commit — this release primarily records the versioning milestone and documentation cleanups.
- If you plan to publish a GitHub Release for `v10.0.0`, create a signed tag and attach the official release ZIP (release automation will run CI checks and VirusTotal scans).
- Token storage note: the repo’s DPAPI blob `.github-token.dpapi` is machine/user-scoped and not portable by hand. If the stored blob is unreadable (for example after moving the folder between machines/users, or if the blob got corrupted), do **not** try to decrypt it manually. Re-save the token through menu `[K]` so the script recreates `.github-token.dpapi` through the normal path (validate against `api.github.com/user`, then write via `ConvertFrom-SecureString`).
- Caveat for manual troubleshooting: the file can legitimately have a UTF-8 BOM (that is why a BOM scan may call it “safe to strip”), but that is separate from whether the DPAPI blob is decryptable. A BOM does not make the blob plaintext, and a `TypeNotFound` on `[System.Security.Cryptography.ProtectedData]` is a runtime availability problem in the shell you ran it from, not proof that the blob is corrupted.

**Notes for maintainers:**
- Consider bumping `$scriptVer` in `mumu-menu.ps1` and `.version` to `10.0.0` (no leading `v`) so the changelog-sync workflow sees consistency.

---

## Notes

- Full historical details are preserved in the Git commit history and GitHub releases if needed.

**Requirements:** Windows 10/11 · PowerShell 5.1+ · MuMu Emulator 6.x

# MuMuManager CLI Menu

Interactive PowerShell menu for managing MuMu Emulator instances through the official `MuMuManager.exe`.

This file contains the release notes for the v10.2.0, v10.1.0 and v10.0.0 milestones. Older per-version blocks have been removed; only the latest entries are kept as requested.

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

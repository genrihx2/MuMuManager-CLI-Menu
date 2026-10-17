# MuMuManager CLI Menu

Interactive PowerShell menu for managing MuMu Emulator instances through the official `MuMuManager.exe`.

This file contains the release notes for the v10.1.0 and v10.0.0 milestones. Older per-version blocks have been removed; only the two latest entries are kept as requested.

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

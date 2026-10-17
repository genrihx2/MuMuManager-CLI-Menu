# @mumu-manager/archil-experiment

Experimental Archil disk persistence integration placed alongside the MuMuManager CLI Menu repo.

This is an experiment, not part of the main MuMu release. It lives in this repo as a convenience
(next to the PowerShell menu) and can be packaged/bundled independently.

## What’s here

- `../archil-storage.mjs` — server-side Archil disk storage module (disk SDK from `disk@1.8.0`).
- `../check-archil-persistence.mjs` — runnable persistence check (`npm run check:archil`).
- `../archil-token.ps1` — Archil token manager with DPAPI (CurrentUser).
- `package.json` — this experiment’s package manifest.
- `release-notes.cjs` — regenerates `release-notes.json` from the manifest + tree/git state.
- `release-notes.json` — machine-readable release/bundle notes (generated; not committed).

## Run

From the repo root:

```powershell
npm run check:archil     # persistence check (needs ARCHIL_API_KEY)
```

Token manager (PowerShell):

```powershell
. .\archil-token.ps1
& { Show-ArchilTokenMenu }
```

## Release notes

This experiment has **machine-readable** release notes only, in `release-notes.json`. They are
generated from the package manifest + repo tree + current git HEAD, and are meant for a bundler or
CI that ships the experiment — not as prose release notes for a human reader.

Regenerate them:

```powershell
node archil\release-notes.cjs
```

The generator is intentionally small and does **not** implement a “select a previous tag” GitHub
release-notes UI. If you want generated prose release notes tied to tags, that is a separate feature
(to build on top of this experiment), not something this package provides today.

## Generated release artifact

`release-notes.json` is generated output. It is intentionally ignored by Git (`.gitignore`); it is
meant to be regenerated on demand rather than committed.

## Scope

This is experimental and separate from the main MuMu release. The main MuMu release workflow and
release ZIP list are unchanged.

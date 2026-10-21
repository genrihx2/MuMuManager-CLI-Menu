# MuMuManager CLI Menu — Archil experiment release runbook

This is a handoff for **publishing the `@mumu-manager/archil-experiment`** release artifact.
It is a local planning doc, not an automated pipeline. Running the steps here requires
state-changing Git actions and possibly npm registry + CI dispatch, which are not done
automatically in this workspace.

## What is being released

- Package: `@mumu-manager/archil-experiment` 0.1.0
- Generated release artifact: `archil/release-notes.json`
- Generator: `archil/release-notes.cjs`
- Readme: `archil/README.md`

The experiment is meant to be shipped as a small independent bundle alongside the main
MuMuManager CLI Menu repo. It is **not** part of the main MuMu release.

## Before running this

1. Decide the shipping mechanism first:
   - npm publish of the experiment package, or
   - attaching the experiment bundle to a MuMu release artifact, or
   - some other distribution channel.
2. Make sure the generated release artifact is up to date:
   ```powershell
   node archil\release-notes.cjs
   ```
3. Confirm the generated artifact looks right:
   - `bundleFiles` should be forward-slash, repo-root-relative paths.
   - `archiveManifest` should list the same files with sizes and paths.
   - `commitish` should be the HEAD you intend to ship.

## Release notes used here

This experiment uses **machine-readable** release notes in `archil/release-notes.json`.
They are generated from the package manifest + tree state + current git HEAD and are meant
for a bundler/CI, not for human prose.

If you want human-readable release notes tied to previous tags, that is a separate feature
(not implemented in this experiment). The GitHub “generate release notes” / “select a previous
tag” workflow is about prose release notes linked to tags; this experiment does not provide that
UI.

## Release steps (template)

1. Regenerate the release artifact:
   ```powershell
   node archil\release-notes.cjs
   ```
2. Verify the generated artifact:
   - inspect `archil/release-notes.json`
   - confirm `bundleFiles` and `archiveManifest` are the files you expect
   - confirm `commitish` matches the intended HEAD
3. Commit the experiment source you intend to ship:
   - `archil/package.json`
   - `archil/README.md`
   - `archil/release-notes.cjs`
   - plus the repo-root files the experiment references:
     - `archil-storage.mjs`
     - `check-archil-persistence.mjs`
     - `archil-token.ps1`
4. Do **not** commit `archil/release-notes.json` as permanent source. It is generated output
   and is ignored by `.gitignore`. Regenerate it from the committed generator when needed.
5. Choose and run the publishing step for your chosen mechanism:
   - npm publish, or
   - attach bundle to a MuMu release, or
   - other distribution channel.
6. After publishing, update any pointers that consumers use to find the experiment
   (readme pointers, package registry links, release artifact manifests, etc.).

## Scope and boundaries

- This runbook is only for the archil experiment release artifact.
- The main MuMu release workflow and main release ZIP list are separate and unchanged.
- Publishing steps that require auth, CI dispatch, or remote git operations are not run
  automatically here; they are described so a human or another automation can execute them.

## Generated artifact notes

- `release-notes.json` is regenerated, not hand-edited.
- It is intentionally ignored by Git; do not treat it as the source of truth for release
  metadata. The source of truth is the generator + the committed experiment files.

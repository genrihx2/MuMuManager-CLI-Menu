# Release Runbook (tag-driven release.yml)

Applies to the tag-driven `.github/workflows/release.yml` plus the CI lint
job (`lint.yml`) and the `virustotal.yml` YAML-parse fix — merged upstream via
PR #13, with shellcheck fixes in `88677d6`. Status: **v1.18.6 backfill done**
(2026-09-14) — official ZIP + SHA256 assets published by CI.

All three release paths end in the same pipeline: **tag → verify `$scriptVer`
matches → build ZIP from tag content → attach ZIP + .sha256 to the release**.

## Path 1 — Release by pushing a tag (recommended)

```bash
# 1. Make sure mumu-menu.ps1 at the tagged commit has $scriptVer = '<version>'
git checkout main && git pull
grep -oP "scriptVer\s*=\s*'\K[\d\.]+" mumu-menu.ps1   # e.g. 1.18.7

# 2. Tag and push
git tag v1.18.7
git push origin main v1.18.7
```

The workflow runs on the tag push and publishes the release. If `$scriptVer`
does not match the tag, the run **fails with an error instead of publishing
an empty release** — fix the mismatch, delete/recreate the tag, and re-run.

## Path 2 — Release by version bump (the classic flow)

Bump `$scriptVer` in `mumu-menu.ps1`, commit, push to `main`. The workflow
reads the version at HEAD, creates and pushes tag `v<version>` if missing,
and releases it. If the tag already exists on origin, the run is a clean no-op.

## Path 3 — Manual dispatch (backfill / re-attach assets)

For an existing tag whose release is missing assets (e.g. v1.18.1–v1.18.6):

1. **Precondition:** `$scriptVer` at the tag must equal the tag version.
   Check first: `git show v1.18.6:mumu-menu.ps1 | grep scriptVer`
2. GitHub → Actions → **Release** → *Run workflow* → enter the tag, e.g. `v1.18.6` → Run.
3. Result: assets appear on the existing release (workflow skips `gh release
   create` for an existing release and **fails** instead — delete the empty
   release first with `gh release delete v1.18.6 --yes`, keep the tag, re-run).

Historical note: v1.18.1–v1.18.5 tags contain `scriptVer = '1.18.0'`, so the
version gate refuses them — they remain tag-only history. v1.18.6 was
backfilled on 2026-09-14: tag re-pointed at corrected `main`, empty release
deleted, and CI published the official ZIP + SHA256 assets.

## Publishing the fix & backfilling GitHub Releases (maintainer)

> ✅ **Executed 2026-09-14:** PR #13 merged, `v1.18.6` re-pointed, empty
> release deleted, CI run #272 published the official ZIP + SHA256 assets.

The workflow fix only takes effect once it is on `main` of the official repo:

```bash
git push origin HEAD:main            # direct push (maintainer), or:
git push origin HEAD:fix/release-pipeline   # then open a PR from it
```

**Backfill v1.18.6 (the current latest release, empty since 2026-09-12):**

```bash
# 1. Re-point the tag at corrected content (current main has scriptVer = 1.18.6)
git tag -f v1.18.6 f3ed722
git push origin v1.18.6 --force       # overwrites the tag on GitHub

# 2. Delete the EMPTY release only (keep the tag!)
gh release delete v1.18.6 --yes      # without --cleanup-tag

# 3. The force-push triggers the new Release workflow ->
#    ZIP + .sha256 are built from the tag and published automatically.
#    If it does not trigger: Actions -> Release -> Run workflow -> tag=v1.18.6
```

**Older empty releases (v1.18.1–v1.18.5):** their tagged `mumu-menu.ps1`
still says `scriptVer = '1.18.0'`, so the version gate will (correctly) refuse
them. Either leave them as tag-only history, delete the empty releases, or —
cleanest — cut a fresh corrected release (e.g. v1.18.7) via Path 1 and let
v1.18.6+ be the verified line.

**VirusTotal scanning (done 2026-09-14):** the repo previously had no
`VT_API_KEY` secret, so every VT run since v1.18.0 skipped its upload
silently ("succeeded" without scanning). The secret is now configured,
workflow run #205 scanned the v1.18.6 release ZIP successfully, and future
releases are scanned automatically on publish. Verdicts (0 malicious /
0 suspicious) are in the README's «Безопасность» section. Caveat: releases
published by the Release workflow's `GITHUB_TOKEN` do not auto-trigger the VT
workflow (GitHub suppresses `GITHUB_TOKEN`-triggered workflows) — dispatch it
manually: Actions → VirusTotal scan → Run workflow → tag = version.

## Landing fixes upstream as an outside contributor (fork + PR)

Reference for future contributions. Used for the release-pipeline fix, which
landed as PR #13 (merged 2026-09-14). If you cannot push directly, go through
a fork.

```bash
# 0. One-time: authenticate (makes steps 1-3 one-liners)
gh auth login

# 1. Fork the repo under your account (no clone needed - worktree is ready)
gh repo fork genrihx2/MuMuManager-CLI-Menu --clone=false

# 2. Add the fork as a remote and push the branch under a clean name
git remote add fork https://github.com/<YOUR-USERNAME>/MuMuManager-CLI-Menu.git
git push -u fork HEAD:fix/release-pipeline

# 3. Open the PR against the official repo
gh pr create \
  --repo genrihx2/MuMuManager-CLI-Menu \
  --base main \
  --head <YOUR-USERNAME>:fix/release-pipeline \
  --title "fix: tag-driven Release workflow + CI lint; repair virustotal.yml YAML" \
  --body-file ISSUE-DRAFT.md
```

No-CLI alternative: fork via the web UI ("Fork" button), push with plain git,
then open the PR from GitHub's "Compare & pull request" banner.

**PR content tips:**

- A good PR description doubles as the issue report (root cause, evidence,
  fix, remediation). Optionally file the issue first and reference it as
  `#N` in the PR so discussion has a stable home.
- If the maintainer prefers email-style patches, generate one with
  `git format-patch origin/main..HEAD --stdout > fix.patch` — it applies
  with `git am`.
- The PR touches only `.github/workflows/release.yml`,
  `.github/workflows/lint.yml`, `.github/workflows/virustotal.yml`,
  `README.md`, `SKILL.md` — no release ZIPs or working artifacts (they are
  untracked on purpose).
- CI on the PR: `lint.yml` runs actionlint + shellcheck on changed
  workflows — fix any findings before merging. Lesson from PR #13: the lint
  job immediately caught pre-existing SC2086/SC2129 issues, fixed in
  `88677d6`.

**After PR #13 merged**, the backfill in the section above was executed:
release v1.18.6 now lists `MuMuManager-CLI-Menu-v1.18.6.zip` +
`.zip.sha256`, published by `github-actions[bot]` (run #272).

## What the workflow guarantees

- ZIP contains exactly `mumu-menu.ps1`, `README.md`, `SKILL.md`, `.version`
  from the tag — never from the branch HEAD.
- Fail-hard if tag/`$scriptVer` mismatch (no more silent empty releases).
- Idempotent: existing release + assets → successful no-op run.
- Users verify downloads the usual way: `sha256sum -c MuMuManager-CLI-Menu-vX.Y.Z.zip.sha256`.

---
name: prep-release
description: Cut a new release of the turbo_bridge / turbo_bridge_client / turbo_bridge_mcp packages. Bumps versions, writes changelogs from git history, runs the publish dry-run locally, watches CI, tags + pushes, monitors the publish pipeline, and rolls back the tag if publish fails. Use when the user says "prep a release", "cut a release", "release vX.Y.Z", or asks to publish to pub.dev.
---

# Prep a release

End-to-end release flow for this workspace. All three packages share one version and one git tag (`vX.Y.Z`).

The publish pipeline (`.github/workflows/publish.yml`) always runs `melos publish --dry-run` first, so a green CI run on the tag implies the dry-run passed in CI too. The point of running it locally first is to catch packaging errors *before* pushing a tag that's hard to take back.

Order of operations matters — don't skip steps, and don't reorder them.

## Inputs

Ask the user for:

- **New version** (`X.Y.Z`). If they don't say, look at the latest tag (`git tag --sort=-v:refname | head -1`) and propose a bump:
  - patch bump for fixes only,
  - minor bump for new public API,
  - major bump for breaking changes.
- **Whether to publish** (default yes) or stop after the dry-run.

Confirm before continuing.

## Steps

### 1. Sanity checks

Run these in parallel:

- `git status` — working tree must be clean. If not, stop and ask.
- `git rev-parse --abbrev-ref HEAD` — should be `main` (or a release branch the user named). If not, ask before continuing.
- `git fetch --tags origin` — make sure tags are current.
- `git tag --sort=-v:refname | head -5` — last few releases for context.
- `git log "$(git describe --tags --abbrev=0)..HEAD" --oneline` — commits since last release. Save this output; it drives the changelog.

If there are no commits since the last tag, stop — there's nothing to release.

### 2. Bump version in every package

Edit `version:` in each `pubspec.yaml`:

- `packages/turbo_bridge/pubspec.yaml`
- `packages/turbo_bridge_client/pubspec.yaml`
- `packages/turbo_bridge_mcp/pubspec.yaml`

Also bump any in-code version constants if they exist (search with `grep -rn "0\.1\.6" packages/*/lib/src/version.dart` style — the previous version's number, not the new one).

Then `melos bootstrap` to refresh lockfiles.

### 3. Write the changelogs

For each package, prepend a `## X.Y.Z` section to `CHANGELOG.md`. Drive the content from the `git log` output captured in step 1, but **filter per package**:

- Group commits by which package they actually touched (use `git log --name-only` if a commit's scope is unclear).
- Don't dump raw commit titles — rewrite as user-facing notes. Each entry is one bullet, present tense ("Add X", "Fix Y"), starting with the change not the conventional-commit prefix.
- Mention behaviour changes, new public API, bug fixes, perf changes, breaking changes. Drop pure refactors, formatting commits, internal test-only changes, and version bookkeeping commits unless they affect users.
- If a package only got a version-bookkeeping change (e.g. `turbo_bridge_mcp` bumping its reported version to track `turbo_bridge`), say exactly that — don't pad the entry.
- Match the wording style of prior entries in that same file (look at the previous version's section to mirror tone).

### 4. Local dry-run

```bash
melos bootstrap
melos publish --dry-run --yes
```

Read every package's output. The only acceptable warning is the "checked-in files are modified in git" notice — that always shows up before the commit lands and goes away in CI. Anything else (missing dependency, format error, analyzer error, oversized archive) is a real failure — fix it before continuing.

### 5. Commit and push to main

```bash
git add packages/*/pubspec.yaml packages/*/CHANGELOG.md pubspec.lock
git commit -m "chore: release vX.Y.Z"
git push origin HEAD
```

### 6. Wait for CI on the release commit

Watch `gh run watch` on the most recent CI run for that commit (`gh run list --branch main --limit 1`). It must go green before tagging. If CI fails, fix forward — don't tag a broken commit.

### 7. Tag and push the tag

```bash
git tag -a vX.Y.Z -m "Release vX.Y.Z"
git push origin vX.Y.Z
```

The tag push triggers `.github/workflows/publish.yml`.

### 8. Monitor the publish pipeline

```bash
gh run watch $(gh run list --workflow=publish.yml --limit 1 --json databaseId --jq '.[0].databaseId')
```

Stream the output. The dry-run step runs first, then the publish step.

### 9. If the publish pipeline fails

Treat this as a rollback-and-redo, not an amend:

1. Delete the tag locally and remotely:
   ```bash
   git tag -d vX.Y.Z
   git push --delete origin vX.Y.Z
   ```
   Confirm the deletion with the user first — `git push --delete` is a remote-mutating action.
2. Diagnose the failure from the workflow logs. Common causes: pub.dev OIDC misconfigured for a new package (needs manual first publish + Admin-tab automation enable), missing dependency exposed only when pub.dev resolves cleanly, format/analyze regression that slipped through.
3. Fix forward with a normal PR / commit on main.
4. Once CI on main is green again, re-tag the **new** commit with the same `vX.Y.Z` and push again.

Do **not** force-push the tag. Always delete + recreate so the trigger fires cleanly.

### 10. After publish succeeds

- Confirm packages appear on pub.dev (`https://pub.dev/packages/turbo_bridge`, `..._client`, `..._mcp`) at the new version.
- Tell the user the release is live and link the workflow run + the pub.dev pages.

## Notes / gotchas

- The three packages share a single version on purpose — don't drift them apart unless the user explicitly asks.
- The publish workflow always runs the dry-run step first, even on a tag push. A failed dry-run aborts the real publish.
- For a `workflow_dispatch` run with `dry-run: true` (the default), only the dry-run executes — useful for testing the pipeline without cutting a release.
- pub.dev refuses lib/ imports of `dev_dependencies`. If you add a new optional adapter, put the dep in `dependencies`, not `dev_dependencies`.

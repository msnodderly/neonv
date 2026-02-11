---
name: create-release
description: "Releases a new version of neonv. Use when asked to release, cut a release, publish a version, or ship."
---

# Releasing

Creat a Release. Complete all steps. Stop.

## Context

Read for additional details:
- `docs/RELEASE.md` — Full release manager's guide
- `AGENTS.md` — br command reference

## Workflow

### 1. Verify Prerequisites

```bash
git checkout main && git pull
git status  # Must be clean
br sync --status
br sync --flush-only
br ready | grep "P0"  # Must return empty
```

### 2. Verify Build

```bash
xcodebuild -project NeoNV/NeoNV.xcodeproj -scheme NeoNV -destination 'platform=macOS' build
```

Must show `** BUILD SUCCEEDED **`.

### 3. Determine Version

```bash
git tag --sort=-v:refname | head -1  # Current version
git log $(git tag --sort=-v:refname | head -1)..HEAD --oneline --no-merges
br list --status closed --limit 20
```

| Changes | Bump | Example |
|---------|------|---------|
| Only `fix:`, `perf:`, `docs:`, `chore:` | Patch | v0.2.0 → v0.2.1 |
| Any `feat:` | Minor | v0.2.1 → v0.3.0 |
| Breaking changes | Major | v0.3.0 → v1.0.0 |

Decide version and proceed. Do not ask for confirmation.

### 4. Tag and Push

```bash
git tag v<VERSION>
git push origin v<VERSION>
```

### 5. Monitor CI

```bash
gh run list --limit 1
gh run watch <run-id> --exit-status
```

CI builds universal binary, creates DMG/ZIP, and publishes GitHub Release.

### 6. Create Release Notes

Extract commit details directly from git:
```bash
# Get feature and fix commits
git log v<PREV_VERSION>..v<VERSION> --oneline --no-merges | grep -E "(feat|fix):"

# Get commit details for each relevant commit
git show <commit-hash> --stat
```

Create `docs/release-notes/v<VERSION>.md`:

```markdown
## NeoNV v<VERSION>

One-sentence summary.

### New Features

- **Feature name** — What users can now do

### Fixes

- **Fix name** — What problem is solved

### Installation

Download the DMG and drag NeoNV to Applications.

**First launch (unsigned app):**
1. Double-click NeoNV — macOS blocks with "cannot be opened"
2. Open **System Settings → Privacy & Security**
3. Click **"Open Anyway"** in Security section
4. Enter password when prompted
```

Only include sections with content. Write from user's perspective.

### 7. Update GitHub Release

```bash
gh release edit v<VERSION> --notes-file docs/release-notes/v<VERSION>.md
```

### 8. Commit Release Notes

```bash
git add docs/release-notes/v<VERSION>.md
git commit -m "docs: Add v<VERSION> release notes"
git push
```

### 9. Update Homebrew Tap

```bash
curl -sL "https://github.com/msnodderly/neonv/releases/download/v<VERSION>/NeoNV-<VERSION>-macos-universal.dmg" -o /tmp/neonv.dmg
shasum -a 256 /tmp/neonv.dmg

cd /tmp && rm -rf homebrew-tap
git clone https://github.com/msnodderly/homebrew-tap.git
```

Edit `/tmp/homebrew-tap/Casks/neonv.rb`:
- Update `version` (without `v` prefix)
- Update `sha256`

```bash
cd /tmp/homebrew-tap
git add Casks/neonv.rb
git commit -m "chore: Update neonv to v<VERSION>"
git push
```

Verify:
```bash
brew update
brew info --cask msnodderly/tap/neonv
```

### 10. Verify

```bash
gh release view v<VERSION>
```

### 11. STOP

Report:
- Version released
- Link: `https://github.com/msnodderly/neonv/releases/tag/v<VERSION>`
- Confirmation that release notes and Homebrew tap were updated

## Troubleshooting

### CI build fails
```bash
gh run view <run-id> --log-failed
```

### Tag already exists
```bash
git tag -d v<VERSION>
git push origin :v<VERSION>
git tag v<VERSION>
git push origin v<VERSION>
```

### Re-run release
```bash
gh release delete v<VERSION> --yes
git push origin :v<VERSION>
git tag -d v<VERSION>
git tag v<VERSION>
git push origin v<VERSION>
```

## Checklist

- [ ] `gh release view v<VERSION>` shows correct release
- [ ] Release notes are curated (not raw commit log)
- [ ] `docs/release-notes/v<VERSION>.md` committed and pushed
- [ ] `git status` shows clean working directory
- [ ] Homebrew tap updated

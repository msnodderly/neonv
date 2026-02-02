# Release Workflow

**Project:** neonv (Swift/SwiftUI macOS app)

## Prime Directive

Release ONE version. Complete all steps. Stop.

Do NOT start additional tasks after the release is complete.

---

## Step 1: Verify Prerequisites

```bash
git checkout main && git pull
git status  # Must be clean
bd sync --full
bd ready | grep "P0"  # Must return empty (no blocking issues)
```

All must pass before proceeding.

---

## Step 2: Verify Build

```bash
xcodebuild -project NeoNV/NeoNV.xcodeproj -scheme NeoNV -destination 'platform=macOS' build
```

Must succeed with `** BUILD SUCCEEDED **`.

---

## Step 3: Determine Version

Get the current version and analyze changes:

```bash
git tag --sort=-v:refname | head -1  # Current version
git log $(git tag --sort=-v:refname | head -1)..HEAD --oneline --no-merges

# Also review closed BD issues for richer context
bd list --status closed --limit 20
```

**Version rules (semantic versioning):**

| Commit prefixes | Bump | Example |
|-----------------|------|---------|
| Only `fix:`, `perf:`, `docs:`, `chore:` | Patch | v0.2.0 → v0.2.1 |
| Any `feat:` | Minor | v0.2.1 → v0.3.0 |
| Breaking changes or major rewrite | Major | v0.3.0 → v1.0.0 |

Review the PR commits since last release and decide the new version and proceed. Do not ask for confirmation.

---

## Step 4: Tag and Push

```bash
git tag v<VERSION>
git push origin v<VERSION>
```

---

## Step 5: Monitor CI

```bash
gh run list --limit 1
gh run watch <run-id> --exit-status
```

CI will:
1. Build universal binary (arm64 + x86_64)
2. Create DMG and ZIP
3. Create GitHub Release with artifacts

Must complete successfully before proceeding.

---

## Step 6: Create Release Notes

**Gather context from BD issues and commits:**

```bash
# Review closed issues for user-facing descriptions
bd list --status closed --limit 20

# For each relevant issue, get full context
bd show <issue-id>
```

BD issues contain richer context than commit messages—use the issue title and description to understand what changed from the user's perspective. Commits provide additional implementation details.

Create `docs/release-notes/v<VERSION>.md` using this template:

```markdown
## NeoNV v<VERSION>

One-sentence summary of the release.

### New Features

- **Feature name** — Description of what users can now do

### Fixes

- **Fix name** — Description of what problem is solved

### Performance

- **Improvement name** — Description of performance gain

### Installation

Download the DMG and drag NeoNV to Applications.

**First launch (app is unsigned):**
1. Double-click NeoNV — macOS will block it with "NeoNV cannot be opened"
2. Open **System Settings → Privacy & Security**
3. Scroll down to the **Security** section
4. Click **"Open Anyway"** next to the NeoNV message
5. Enter your password when prompted

After this one-time setup, NeoNV opens normally.


**Guidelines:**
- Only include sections with content (omit empty sections)
- Write from the user's perspective, not the developer's
- Omit chore commits, syncs, and worktree housekeeping
- Use backticks around `@done` to avoid GitHub mentions

---

## Step 7: Update GitHub Release

```bash
gh release edit v<VERSION> --notes-file docs/release-notes/v<VERSION>.md
```

---

## Step 8: Commit Release Notes

```bash
git add docs/release-notes/v<VERSION>.md
git commit -m "docs: Add v<VERSION> release notes"
git push
```

---

## Step 9: Update Homebrew Tap (Automated)

The Homebrew tap is updated automatically by CI after the GitHub Release is created.

**Prerequisites:** The `HOMEBREW_TAP_TOKEN` secret must be configured in the repo settings (a PAT with `repo` scope for `msnodderly/homebrew-tap`).

**Verify it worked:**
```bash
brew update
brew info --cask msnodderly/tap/neonv  # Should show new version
```

**Manual fallback** (if CI fails or `HOMEBREW_TAP_TOKEN` is not set):

1. Download the DMG and compute SHA256:
   ```bash
   curl -sL "https://github.com/msnodderly/neonv/releases/download/v<VERSION>/NeoNV-<VERSION>-macos-universal.dmg" -o /tmp/neonv.dmg
   shasum -a 256 /tmp/neonv.dmg
   ```

2. Clone, update, and push:
   ```bash
   cd /tmp && rm -rf homebrew-tap
   git clone https://github.com/msnodderly/homebrew-tap.git
   cd homebrew-tap
   # Edit Casks/neonv.rb: update version and sha256
   git add Casks/neonv.rb
   git commit -m "chore: Update neonv to v<VERSION>"
   git push
   ```

---

## Step 10: Verify

```bash
gh release view v<VERSION>
```

Confirm:
- [ ] Release notes display correctly
- [ ] DMG and ZIP artifacts are attached
- [ ] Release is not marked as prerelease (unless intended)

---

## Step 11: STOP

You are done. Do NOT:
- Start another release
- Pick a task to implement
- Make any code changes

Report to the user:
- Version released (e.g., `v0.2.1`)
- Link to release: `https://github.com/msnodderly/neonv/releases/tag/v<VERSION>`
- Confirmation that release notes were updated

---

## Troubleshooting

### CI build fails

Check Xcode version and retry:
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

### Need to re-run release

Delete the release and tag from GitHub, then re-push:
```bash
gh release delete v<VERSION> --yes
git push origin :v<VERSION>
git tag -d v<VERSION>
git tag v<VERSION>
git push origin v<VERSION>
```

---

## Verification Checklist

Before reporting completion:

- [ ] `gh release view v<VERSION>` shows correct release
- [ ] Release notes are curated (not raw commit log)
- [ ] `docs/release-notes/v<VERSION>.md` committed and pushed
- [ ] `git status` shows clean working directory
- [ ] Homebrew tap updated (`brew info --cask msnodderly/tap/neonv` shows new version)

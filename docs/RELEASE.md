# Release Manager's Guide

How to release a new version of neonv.

---

## Quick Reference

```bash
# 1. Ensure main is clean and synced
git checkout main && git pull && bd sync --full

# 2. Tag and push (triggers CI release)
git tag v0.2.0
git push origin v0.2.0
```

CI builds the artifacts and creates the GitHub Release automatically.

---

## Full Release Process

### Pre-Release Checklist

1. **Verify main is stable**
   - All PRs merged
   - Build passes: `xcodebuild -project NeoNV/NeoNV.xcodeproj -scheme NeoNV -destination 'platform=macOS' build`
   - No open P0 issues: `bd ready`

2. **Sync issues**
   ```bash
   bd sync --full
   ```

3. **Clean up worktrees** (if any)
   ```bash
   bd worktree list
   # Remove merged worktrees
   bd worktree remove <name>
   ```

### Create the Release

1. **Choose version number** (semantic versioning)
   - `v0.1.0` → `v0.2.0` for new features
   - `v0.2.0` → `v0.2.1` for bug fixes
   - `v0.2.1` → `v1.0.0` for major/breaking changes

2. **Tag and push**
   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```

3. **Monitor CI**
   ```bash
   gh run list --limit 3
   gh run watch <run-id> --exit-status
   ```
   CI will:
   1. Build universal binary (arm64 + x86_64)
   2. Create DMG and ZIP
   3. Create GitHub Release with artifacts
   4. Auto-generate release notes from commits

4. **Update release notes** (if using custom notes)
   ```bash
   # CI auto-generates notes from commits; replace with custom notes:
   gh release edit v0.2.0 --notes-file docs/release-notes-v0.2.0.md
   ```

### Post-Release

1. **Verify the release**
   - Check: https://github.com/msnodderly/neonv/releases
   - Download and test the DMG

2. **Update Homebrew tap** (if maintained)
   ```bash
   # Update SHA in cask formula
   shasum -a 256 neonv-v0.2.0-macos-universal.dmg
   # Submit PR to homebrew-tap repo
   ```

---

## Manual Build (Local Testing)

For testing release builds locally before tagging:

```bash
./scripts/build-release.sh -v test-build

# Artifacts created in ./release/:
#   neonv-test-build-macos-universal.dmg
#   neonv-test-build-macos-universal.zip
```

---

## Artifact Naming Convention

```
NeoNV-{version}-macos-universal.dmg
NeoNV-{version}-macos-universal.zip
```

Examples:
- `NeoNV-0.2.0-macos-universal.dmg`
- `NeoNV-dev-7a0705c-macos-universal.dmg` (dev builds)

---

## Prerelease Versions

Tags with hyphens (e.g., `v0.3.0-beta.1`) are marked as prereleases on GitHub automatically.

---

## CI Workflow Summary

| Trigger | What Happens |
|---------|--------------|
| PR to main | Build verification only (no artifacts) |
| Push tag `v*.*.*` | Full release: build → sign (if secrets) → GitHub Release |

---

## Signing & Notarization

**Current state:** Unsigned builds only (no Apple Developer account).

Users see Gatekeeper warning and must right-click → Open.

**To enable signing later:**
1. Obtain Apple Developer ID ($99/yr)
2. Add secrets to GitHub repo:
   - `APPLE_DEVELOPER_ID_APPLICATION`
   - `APPLE_DEVELOPER_ID_PASSWORD`
   - `APPLE_TEAM_ID`
3. CI will automatically sign and notarize (pipeline already supports this)

---

## Troubleshooting

### CI build fails
- Check Xcode version in `.github/workflows/ci.yml`
- Verify build works locally: `./scripts/build-release.sh`

### Tag already exists
```bash
git tag -d v0.2.0           # Delete local
git push origin :v0.2.0     # Delete remote
git tag v0.2.0              # Re-create
git push origin v0.2.0
```

### Need to re-run release
Delete the release and tag from GitHub, then re-push the tag.

---

## Writing Release Notes

For major releases, create a custom release notes file:

```bash
# Create release notes file (use v0.1.0 as template)
cp docs/release-notes/v0.1.0.md docs/release-notes/v0.2.0.md
# Edit as needed, then update the GitHub release after CI creates it
```

**Important:** Use backticks around `@done` when referring to the Taskpaper-style feature to avoid GitHub interpreting as user tags.

---

## Related Docs

- [Packaging, Release & CI/CD Design](plans/packaging-release-cicd.md) — full design rationale
- [scripts/build-release.sh](../scripts/build-release.sh) — local build script
- [.github/workflows/ci.yml](../.github/workflows/ci.yml) — CI workflow

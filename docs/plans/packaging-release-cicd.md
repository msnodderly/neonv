# Packaging, Release & CI/CD Design

**Project:** NeoNV (Swift/SwiftUI macOS app)
**Status:** Draft — for collaborative review
**Date:** 2026-01-31

---

## Current State

- Build: manual `xcodebuild` via `run.sh` (Debug) or CLI (Release)
- Signing: Automatic, no paid Apple Developer account
- Distribution: None — development-only
- CI/CD: None
- Version: 0.1.0 (build 1)
- Bundle ID: `net.area51a.NeoNV`
- Deployment target: macOS 14.0+, universal binary
- Hardened runtime + App Sandbox enabled

---

## Constraints

- **No paid Apple Developer Program ($99/yr)** — rules out:
  - Notarization (requires Developer ID certificate)
  - Developer ID signing (requires paid account)
  - Mac App Store distribution
  - TestFlight distribution
- **Must remain practical** for a solo/small-team project

---

## Distribution Options Without Paid Account

### Option A: Unsigned DMG (simplest)

**How it works:** Build Release `.app`, package into a `.dmg`, distribute via GitHub Releases.

**User experience:**
- macOS shows "app can't be opened because it is from an unidentified developer"
- User must right-click > Open (or System Settings > Privacy & Security > Open Anyway)
- Gatekeeper warning on every new download
- On macOS 15+, this flow is slightly more buried but still works

**Pros:**
- Zero cost, zero Apple dependency
- Simple automation
- Common for open-source macOS apps (Neovim, Alacritty, etc.)

**Cons:**
- Scary UX for non-technical users
- `xattr -cr` or right-click needed every time
- Hardened runtime still works, but quarantine flag triggers Gatekeeper

**Automation complexity:** Low

---

### Option B: Unsigned ZIP via GitHub Releases

Same as Option A but as a `.zip` instead of `.dmg`. Slightly simpler to produce (no `hdiutil`). Same Gatekeeper warnings. Less polished (no drag-to-Applications experience).

---

### Option C: Homebrew Cask (community distribution)

**How it works:** Create a Homebrew cask formula pointing to GitHub Releases artifacts. Users install with `brew install --cask neonv`.

**User experience:**
- `brew install --cask neonv` — familiar for developers
- Homebrew handles quarantine removal automatically
- Updates via `brew upgrade`

**Pros:**
- No Gatekeeper warnings (Homebrew strips quarantine)
- Developer-friendly install/update flow
- No Apple account needed

**Cons:**
- Only reaches Homebrew users (developer audience)
- Maintaining the cask formula (can be in your own tap)
- Still unsigned — manual download still triggers Gatekeeper

**Automation complexity:** Medium (need to update cask SHA on each release)

---

### Option D: Paid Account (for reference)

Cost: $99/year. Unlocks notarization, Developer ID signing, TestFlight, Mac App Store. Mentioned for completeness — currently out of scope.

---

## Recommended Approach

**Option A (DMG) + Option C (Homebrew Cask)** — cover both direct-download and developer-friendly channels without Apple account dependency.

---

## CI/CD Pipeline Design

### GitHub Actions Workflow

```
Trigger: push tag v*.*.*
  │
  ├─ Build Job
  │   ├─ Checkout
  │   ├─ Select Xcode version
  │   ├─ Build Release (xcodebuild archive)
  │   ├─ Export .app from archive
  │   ├─ Package .dmg (hdiutil)
  │   ├─ Package .zip (ditto)
  │   ├─ Upload artifacts
  │   │
  │   └─ (Future: notarize step — gated behind HAS_SIGNING_IDENTITY secret)
  │
  └─ Release Job (depends on Build)
      ├─ Create GitHub Release from tag
      ├─ Attach .dmg and .zip
      └─ Generate release notes from commits
```

### Key Design Decisions

**1. Trigger: Git tags, not branches**
- Push `v0.2.0` tag to trigger release
- PRs and main pushes only run build verification (no release)

**2. macOS runner**
- GitHub provides `macos-14` (Sonoma) runners — free for public repos, 10x cost for private
- Private repo: consider self-hosted runner on a Mac

**3. Signing strategy (future-proof)**
- Build pipeline has an optional signing/notarization step
- Controlled by presence of secrets (`DEVELOPER_ID_APPLICATION`, `APPLE_ID`, etc.)
- When secrets absent: skip signing, produce unsigned artifacts
- When secrets present: sign + notarize automatically
- This means adding a paid account later requires zero pipeline changes

**4. Version management**
- Source of truth: git tag
- Pipeline injects version into `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` at build time
- No manual Info.plist edits needed

**5. Artifact naming**
- `NeoNV-{version}-macos-universal.dmg`
- `NeoNV-{version}-macos-universal.zip`

---

## Build Script (`scripts/build-release.sh`)

Responsibilities:
1. Accept version as argument (or read from git tag)
2. `xcodebuild archive` with Release configuration
3. Export `.app` from archive
4. Create DMG via `hdiutil`
5. Create ZIP via `ditto`
6. Output paths for CI to upload

This script should work identically on local machines and CI.

---

## Homebrew Tap

Create `homebrew-tap` repo (e.g., `github.com/<user>/homebrew-tap`) containing:

```ruby
cask "neonv" do
  version "0.2.0"
  sha256 "<sha256-of-dmg>"

  url "https://github.com/<user>/neonv/releases/download/v#{version}/NeoNV-#{version}-macos-universal.dmg"
  name "NeoNV"
  desc "Lightweight macOS note editor"
  homepage "https://github.com/<user>/neonv"

  app "NeoNV.app"
end
```

**Automation:** GitHub Actions on the neonv repo can auto-PR the tap repo with updated version/SHA after each release.

---

## Release Process (Manual Steps)

1. Update changelog (if maintained)
2. Tag: `git tag v0.2.0 && git push origin v0.2.0`
3. CI builds, creates GitHub Release with artifacts
4. (Optional) Update Homebrew tap

---

## Tradeoff Summary

| Concern | Unsigned DMG | Homebrew Cask | Paid Account |
|---------|-------------|---------------|--------------|
| Cost | $0 | $0 | $99/yr |
| Gatekeeper warning | Yes | No (brew strips) | No |
| Non-technical users | Poor UX | N/A | Good UX |
| CI complexity | Low | Medium | Medium-High |
| Auto-update | Manual | `brew upgrade` | Sparkle/TestFlight |
| Apple dependency | None | None | Full |

---

## Future Considerations

- **Sparkle framework**: In-app auto-update, works without Apple account, adds update checking to the app itself. Worth considering once there's a user base.
- **Paid account**: If NeoNV targets non-developer users, notarization becomes important for UX. The pipeline is designed to add this with zero rework.
- **Private repo costs**: GitHub Actions macOS minutes are 10x on private repos. Self-hosted runner or switching to public may be relevant.

---

## Open Questions

1. Is the repo public or private? (Affects GitHub Actions cost and Homebrew tap feasibility)
2. Should we add a Sparkle-based auto-updater now or defer?
3. Any preference on changelog format (CHANGELOG.md, GitHub Release notes only, or both)?
4. Should CI also run on PRs (build-only, no release) as a quality gate?

---

## Roadmap

_To be decided after review._

- [ ] Phase 1: Build script (`scripts/build-release.sh`)
- [ ] Phase 2: GitHub Actions CI (build on PR, release on tag)
- [ ] Phase 3: Homebrew tap
- [ ] Phase 4: (Optional) Sparkle auto-updater
- [ ] Phase 5: (Optional) Paid account + notarization

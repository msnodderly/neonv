# neonv

A minimal, low friction text capture tool for macOS. Store snippets, thoughts, notes, and random text, find them instantly, never think about saving.

Inspired by [Notational Velocity](https://notational.net/)'s speed and simplicity, built for modern macOS.

This was built partially as an excuse to learn and experiment with AI coding tools, and trying to find a viable way to use them to build what I hope is high quality software.

Bug reports and feature requests are accepted, preferably in the form of a coding agent prompt. As of Feb 2026 I consider this project essentially feature-complete. -Matt

## Philosophy

**Do one thing and do it well:** Capture and retrieve text instantly.

## Features

- **Instant Capture** — One text box, always ready. Auto-saves continuously.
- **Instant Search** — Fuzzy full-text search as you type. Results appear immediately.
- **Zero Friction Storage** — Point at any folder with text files in it. Files are plain `.txt`, `.md`, or `.org`. No databases.
- **Wiki Links** — Wiki-style `[[target]]` and `[[target|label]]` links in editor and preview. Cmd-click opens links.

## Screenshots

Mac app icon:

<a href="img/neonv-mac-icon.png">
  <img src="img/neonv-mac-icon.png" alt="NeoNV macOS app icon" width="128" height="128">
</a>

### Light Theme

![NeoNV light theme](img/screenshots/light-theme.webp)

### Markdown Preview

![NeoNV markdown preview](img/screenshots/markdown-preview.webp)

### Org Mode Preview

![NeoNV org mode preview](img/screenshots/orgmode-preview.webp)

### Org Mode Editing

![NeoNV org mode editing](img/screenshots/orgmode.webp)

### Tags And Vertical Layout

![NeoNV tags and vertically stacked mode](img/screenshots/tags-and-vertically-stacked-mode.webp)

## Installation

### Homebrew (Recommended)

```bash
brew install --cask msnodderly/tap/neonv
```

### Manual Download

1. Download the latest DMG from [GitHub Releases](https://github.com/msnodderly/neonv/releases)
2. Open the DMG and drag NeoNV to Applications
3. **First launch (app is unsigned):**
   - Double-click NeoNV — macOS will block it
   - Open **System Settings → Privacy & Security**
   - Scroll to **Security**, click **"Open Anyway"**

## Building from Source

Open `NeoNV.xcodeproj` in Xcode 15+ and build (⌘B).

```bash
xcodebuild -scheme NeoNV -configuration Release
```

## License
This repo contains no code from Notational Velocity but is heavily inspired by it and as such it's released under the same license.

NeoNV is free software licensed under the [GNU General Public License v3.0](LICENSE).

# neonv

A fast, low friction text capture tool for macOS. Store snippets, thoughts, notes, and random text, find them instantly, never think about saving.

Inspired by [Notational Velocity](https://notational.net/)'s speed and simplicity, built for modern macOS.

Bug reports and feature requests are accepted, preferably in the form of conding agent prompts. As of Feb 2026 I consider this project essentially feature-complete. -Matt

## Philosophy

**Do one thing and do it well:** Capture and retrieve text instantly.

## Features

- **Instant Capture** — One text box, always ready. Auto-saves continuously.
- **Instant Search** — Fuzzy full-text search as you type. Results appear immediately.
- **Zero Friction Storage** — Point at any folder with text files in it. Files are plain `.txt`, `.md`, or `.org`. No databases.
- **Wiki Links** — Wiki-style `[[target]]` and `[[target|label]]` links in editor and preview. Cmd-click opens links.
- **Tab-Based Wiki Autocomplete** — Hit Tab to autocomplete inside `[[...]]`

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

NeoNV is free software licensed under the [GNU General Public License v3.0](LICENSE).

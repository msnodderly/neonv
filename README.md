# neonv

A fast, frictionless text capture tool for macOS. Store snippets, thoughts, notes, and random text without friction. Find them instantly. Never think about saving.

Inspired by [Notational Velocity](https://notational.net/)'s speed and simplicity, built native for modern macOS.

## Philosophy

**Do one thing perfectly:** Capture and retrieve text instantly.

## Features

- **Instant Capture** — One text box, always ready. Auto-saves continuously.
- **Instant Search** — Fuzzy full-text search as you type. Results appear immediately.
- **Zero Friction Storage** — Point at any folder. Files are plain `.txt`, `.md`, or `.org`. No database, no lock-in.
- **Native Performance** — macOS-native Swift/SwiftUI. Optimized for Apple Silicon. Instant everything.

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon or Intel Mac (universal binary)

## Installation

### Homebrew (Recommended)

```bash
brew install --cask msnodderly/tap/neonv
```

This is the easiest way to install NeoNV. Homebrew handles the download and installation automatically.

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


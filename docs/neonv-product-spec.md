# neonv: Product Specification

## Vision

A fast, frictionless text capture tool for macOS. Store snippets, thoughts, notes, and random text without friction. Find them instantly. Never think about saving.

Inspired by Notational Velocity's legendary speed and simplicity, built native for modern macOS.

## Core Philosophy

**Do one thing perfectly:** Capture and retrieve text instantly.

This is not a note-taking system. Not a knowledge base. Not a productivity tool. It's a place to put text so you can find it later.

## The Problem We Solve

Where do you put:

- A code snippet you just found
- Text you're editing before pasting into Slack
- A random thought while walking
- Technical notes that don't need structure
- The fix for "oops I hit Enter too soon in this text box"

You need somewhere fast, searchable, and permanent. Not a temporary scratchpad. Not an elaborate note system. Just a text box that remembers.

---

## Core Features

### Instant Capture

- One text box, always ready
- Paste removes formatting automatically
- Auto-saves continuously—never think about saving
- Speech-to-text input (integrates with Superwhisper or system dictation)
- Fast enough to interrupt your workflow, light enough to keep open always

### Instant Search

- Fuzzy full-text search as you type
- Results appear immediately
- No indexing delays, no "building library"
- Search across thousands of files in milliseconds

### Zero Friction Storage

- Point the app at any folder
- Files are just `.txt`, `.md`, or `.org`—your choice
- No database, no proprietary format, no lock-in
- Files can be edited by any tool—the app doesn't care
- Nested directories supported; UI shows flat list of all files

### Smart File Handling

- New notes created instantly with first line as filename
- Most recently edited files at the top
- Opening is instantaneous—no loading states
- Everything in plain text, readable by humans and machines

---

## What It Doesn't Do (Anti-Features)

| Anti-Feature | Rationale |
|--------------|-----------|
| **No Sync** | Use iCloud, Dropbox, or any sync solution. We won't break them, we won't replace them. |
| **No Network Access** | The core app never touches the network. Ever. Your data stays local unless YOU sync it elsewhere. |
| **No Rich Text** | Plain text or markdown preview only. No fonts, no colors, no formatting beyond basic markdown rendering. |
| **No Social Features** | No sharing, no collaboration, no server-side anything. Single-player tool. |
| **No Complex Organization** | No mandatory tags, no required metadata, no forced structure. Directories are optional. Search is mandatory. |

---

## Technical Principles

### Plain Text, Plain Files

- Store format: UTF-8 text files
- No database (except optional in-memory index for performance)
- Filesystem is the source of truth
- Any tool can read/edit these files

### Format Agnostic Core

- Works with `.txt`, `.md`, `.org`, or any text file
- Doesn't parse or interpret syntax in core editor
- Shows raw text by default
- Optional preview plugins can render formats

### Org-Mode Peaceful Coexistence

- Never corrupts org-mode files
- Preserves headings, properties, timestamps, and syntax
- Doesn't interpret org-mode syntax unless plugin enabled
- If you use Emacs with org-mode, your files still work perfectly
- If you don't use Emacs, the app is still perfectly useful

### Native Performance

- macOS-native using Swift/SwiftUI + AppKit
- Optimized for Apple Silicon
- Instant startup, instant search, instant everything
- Wastes RAM before creating any friction

---

## User Experience

### The Interface

```
┌─────────────────────────────────────────────┐
│ [Search box]                                │
├──────────────┬──────────────────────────────┤
│ File List    │ Editor Pane                  │
│              │                              │
│ > Note 1     │ [Your text here]             │
│   Note 2     │                              │
│   Note 3     │                              │
│   ...        │                              │
│              │                              │
└──────────────┴──────────────────────────────┘
```

Optional preview pane can be toggled for markdown/org rendering.

### The Workflow

1. Open app (always running, instant)
2. Start typing or paste
3. Search filters as you type
4. Click a result to edit
5. Everything saves automatically

That's it.

---

## Keyboard Navigation (Non-Negotiable)

*Added based on prototype testing, January 2026*

The app must be fully keyboard-navigable. **Every beep is a bug.**

### The Beep Audit Principle

> If the user presses a key and hears a system beep, we have failed to handle an expected action.

During development, track beeps and implement sensible defaults for each unexpected key combination.

### Focus Cycle

```
Search ←→ Note List ←→ Editor/Preview
        Tab/↓           Tab
       Shift-Tab      Shift-Tab
```

### Default Focus States

- **App launch:** Search box focused, ready to type immediately
- **After creating new note:** Editor focused
- **After deleting note:** List focused (or search if list empty)

### Navigation Key Mappings

| Context | Key | Action |
|---------|-----|--------|
| Search | Tab | Select first filtered note, focus list |
| Search | Down Arrow | Select first filtered note, focus list |
| Search | Up Arrow | Do nothing (stay in search, no beep) |
| Search | Enter | Create new note with search text as title |
| List | Tab | Focus editor |
| List | Shift-Tab | Focus search |
| List | Up/Down | Navigate notes |
| List | Enter | Focus editor for selected note |
| Editor | Shift-Tab | Focus list (keep selection) |
| Editor | Tab | Insert tab character |
| Preview | Shift-Tab | Focus list |
| Preview | Any letter/number | Switch to editor, capture keystroke |
| Preview | Up/Down | Scroll content |
| Anywhere | Cmd-L | Focus search |
| Anywhere | Esc | Focus search, clear selection |
| Anywhere | Cmd-P | Toggle preview |

### Essential Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| **Cmd-L** | Focus search bar |
| **Cmd-P** | Toggle preview mode |
| **Cmd-N** | New note |
| **Cmd-Z** | Undo |
| **Cmd-Shift-Z** | Redo |
| **Cmd-A** | Select all in current pane |
| **Esc** | Return to search |
| **Tab** | Next pane (Search → List → Editor) |
| **Shift-Tab** | Previous pane |

---

## File Display & Naming

*Added based on prototype testing, January 2026*

### Note List Display

Each note in the list shows two lines:

```
Meeting with design team
  work/meeting-notes.md
```

- **Line 1 (title):** First ~50 characters of first line, markdown stripped
- **Line 2 (path):** Relative path + filename, muted color

### Markdown Stripping for Display

Remove leading formatting from display title only (file content unchanged):

| Raw First Line | Displayed As |
|----------------|--------------|
| `# Meeting Notes` | `Meeting Notes` |
| `## Project Update` | `Project Update` |
| `- Buy milk` | `Buy milk` |
| `* Task item` | `Task item` |
| `> Important quote` | `Important quote` |

### Unsaved Note Indicator

New notes that haven't been saved to disk show:

```
My new note title
  notes/[unsaved]          ← orange, italic
```

Once saved, shows actual filename:

```
My new note title
  notes/my-new-note-title.md
```

### Filename Generation Rules

When saving a new note:

1. Take first line of content
2. Sanitize: lowercase, replace spaces with hyphens, remove special characters
3. Truncate to ~100 characters (filesystem safe)
4. Add configured extension (`.md`, `.txt`, `.org`)
5. If file exists, append numeric suffix (`-2`, `-3`, etc.)

**Fallback:** If first line is empty/whitespace, use `untitled-[timestamp].ext`

---

## Preview Mode

*Added based on prototype testing, January 2026*

### Toggle Behavior

- **Keyboard:** Cmd-P toggles preview on/off
- **Button:** Toggle button next to search bar
- **Position:** Preview replaces editor pane (not side-by-side)

### Preview Must Be Keyboard-Accessible

- Preview pane receives focus when activated
- **Up/Down arrows:** Scroll content
- **Page Up/Page Down:** Scroll by page
- **Shift-Tab:** Return to note list

### Smart Edit Switching

When in preview mode and user types any letter/number:

1. Instantly switch to editor mode
2. Focus editor
3. Capture the keystroke in editor

This eliminates "why isn't my typing working?" confusion.

### Rendering (MVP)

- Markdown: Headers, lists, bold, italic, links, code blocks
- Plain text: Show as-is
- Org-mode: Show as plain text (plugin later)

---

## Development Phases

### Phase 0: Setup (Before Coding)

**Goal:** Eliminate blockers before writing code

- [ ] Create GitHub repo
- [ ] Set up Xcode project with universal binary target
- [ ] Verify you can build and run locally (free Apple ID is sufficient)

**Exit Criteria:** Can build and run the app on your own Mac

### Apple Developer Account: When Do You Actually Need It?

**Short answer:** Not until you want to distribute to others.

| What You Want To Do | Free Apple ID | Paid Developer Account ($99/yr) |
|---------------------|---------------|--------------------------------|
| Build and run on your own Mac | ✅ Yes | Not needed |
| Debug and develop locally | ✅ Yes | Not needed |
| Run on your own devices indefinitely | ✅ Yes | Not needed |
| Distribute unsigned .app to yourself | ✅ Yes | Not needed |
| Share with others (they must disable Gatekeeper) | ⚠️ Technically works | Not needed |
| Distribute via DMG that "just works" | ❌ No | ✅ Required |
| Homebrew Cask | ❌ No | ✅ Required |
| Mac App Store | ❌ No | ✅ Required |
| Notarization (no Gatekeeper warnings) | ❌ No | ✅ Required |

**For your own use:** Free Apple ID is all you need. Build in Xcode, run it, use it daily. No code signing ceremony required for personal use.

**For distribution:** You'll need the $99/year account to sign and notarize. Without it, other users get scary "unidentified developer" warnings and have to right-click → Open or disable Gatekeeper entirely.

**Recommendation:** Start with free Apple ID. Only pay for the developer account when/if:
1. You've validated the app through daily use (Phase 3 complete)
2. You actually want to share it with others
3. You're confident you'll maintain it

No point spending $99/year on something you might abandon in week 2.

### Phase 1: MVP (Week 1–2)

**Goal:** Functional capture and retrieval with bulletproof saving

- [ ] Text editor window
- [ ] File list (sorted by modification time)
- [ ] Save on keystroke (atomic write with verification)
- [ ] Loud failure on save error (modal, blocks further editing)
- [ ] Basic fuzzy search
- [ ] Unified search/create bar
- [ ] Single folder support
- [ ] Search box focused on launch
- [ ] Tab cycles through panes (Search → List → Editor)
- [ ] Shift-Tab cycles backward
- [ ] Down arrow from search selects first note
- [ ] No beeps for standard navigation keys
- [ ] First-line-as-filename display in list
- [ ] Markdown stripped from display titles
- [ ] Unsaved note indicator (`[unsaved]` in orange)

**Exit Criteria:** Can capture, save, and retrieve text faster than any alternative. Save failures are impossible to miss. Full keyboard navigation without beeps.

### Phase 2: Polish (Week 3–4)

**Goal:** Daily-driver quality

- [ ] Markdown preview toggle (Cmd-P)
- [ ] Preview pane keyboard scrolling (Up/Down, Page Up/Down)
- [ ] Type-to-exit preview mode (any keystroke switches to editor)
- [ ] Cmd-L to focus search from anywhere
- [ ] Full keyboard shortcut implementation
- [ ] Undo/Redo working correctly (Cmd-Z, Cmd-Shift-Z)
- [ ] Settings panel (folder selection, file extension preference)
- [ ] Performance optimization for 1000+ files
- [ ] Global hotkey to summon app
- [ ] External edit detection (FSEvents) with auto-reload
- [ ] Conflict detection (external change while buffer dirty)
- [ ] Nested folder display with path in subtitle

**Exit Criteria:** No friction points that make me reach for another tool. Zero beeps during normal use.

### Phase 3: Live With It (Month 2–3)

**Goal:** Prove the concept through daily use

- [ ] Use it daily for all text capture
- [ ] Fix annoying things as discovered
- [ ] Resist feature creep
- [ ] Document edge cases and pain points

**Exit Criteria:** 30+ consecutive days of daily use

### Phase 4: Distribution Setup (If Sharing With Others)

**Goal:** Enable frictionless installation for other users

**Prerequisites:** 
- Phase 3 complete (you're actually using it daily)
- Decision to share publicly

**Tasks:**
- [ ] Apple Developer account ($99/year)
- [ ] Developer ID Application certificate
- [ ] Set up notarization pipeline (can be manual initially)
- [ ] Test signed/notarized build installs cleanly
- [ ] Create DMG with drag-to-install layout
- [ ] Set up GitHub Releases
- [ ] Submit Homebrew Cask formula

**Exit Criteria:** Someone else can `brew install --cask alt-nv` and it just works

### Phase 5: Plugin Architecture (If Still Using Daily)

**Goal:** Extensibility without complexity

- [ ] Define plugin API
- [ ] Build markdown preview as first plugin
- [ ] Document plugin development
- [ ] Consider open-sourcing plugin system

---

## Post-MVP Features (Maybe)

### Editor Integration

- `Cmd+E` to open current note in $EDITOR (vim, emacs, VS Code)
- Returns to app when editor closes

### Plugin Ideas

| Plugin | Description | Dependency |
|--------|-------------|------------|
| Markdown Preview | Render markdown in preview pane | None |
| Org-Mode Preview | Display org headings and basic syntax | None |
| AI Concept Search | Semantic search using local LLM | Ollama |
| Auto-Titling | Generate filenames from content | Local 3B model |
| Webhook Triggers | Notify external systems on file changes | User-configured |
| Image Reference | Handle image links/attachments | TBD |

All plugins integrate with user-configured tools. No cloud services.

### Maybe Someday

- iOS companion app (read-only? capture-only?)
- Wiki-style linking between notes
- Image paste/preview
- Quick Look integration

---

## Technical Stack

### Language Selection

**Goal:** Native macOS app, single self-contained binary, zero runtime dependencies, fast UI.

| Language | Native macOS GUI | Single Binary | Performance | Distribution Simplicity | Learning Curve (for you) |
|----------|------------------|---------------|-------------|------------------------|--------------------------|
| **Swift** | ✅ First-class (SwiftUI/AppKit) | ✅ Yes | ✅ Excellent | ✅ Apple's blessed path | ⚠️ Medium |
| **Objective-C** | ✅ First-class (AppKit/Cocoa) | ✅ Yes | ✅ Excellent | ✅ Apple's blessed path | ⚠️ Medium (dated syntax) |
| **Rust** | ⚠️ Possible but awkward | ✅ Yes | ✅ Excellent | ⚠️ Extra work for .app bundle | ⚠️ Medium-High |
| **Go** | ❌ Poor | ✅ Yes | ✅ Good | ❌ No good macOS GUI story | N/A |

### Detailed Analysis

#### Swift
**Pros:**
- SwiftUI is genuinely fast to build with for standard macOS UI patterns
- AppKit available for anything SwiftUI can't do
- Xcode handles signing, notarization, universal binaries automatically
- Best documentation for macOS-specific APIs (FSEvents, etc.)
- Apple's investment ensures long-term support

**Cons:**
- Xcode-dependent (heavy IDE)
- Swift version churn (less of an issue now, but historically painful)
- SwiftUI still has rough edges, may need AppKit fallbacks

**Verdict:** Path of least resistance for a native macOS app.

#### Objective-C
**Pros:**
- Rock solid, battle-tested
- AppKit is mature and full-featured
- Interops perfectly with system frameworks
- Stable—no language churn

**Cons:**
- Verbose, dated syntax (brackets everywhere)
- Apple's investment is in Swift now
- Fewer modern tutorials/examples
- No SwiftUI (would need to use AppKit only)

**Verdict:** Would work fine, but no advantage over Swift. More friction, less community momentum.

#### Rust
**Pros:**
- Excellent performance
- Memory safety guarantees
- Single binary, no runtime
- Good cross-platform story if you ever want Linux/Windows

**Cons:**
- No first-class macOS GUI framework
- Options are awkward:
  - **Tauri:** Web-based UI (Electron-lite). Not truly native.
  - **objc2 crate:** Raw Objective-C bindings. You're writing AppKit in Rust with extra steps.
  - **Druid/Iced/egui:** Cross-platform GUI libs. Not native look-and-feel.
- Code signing/notarization requires manual setup
- .app bundle creation requires extra tooling
- Fighting the platform instead of working with it

**Verdict:** Great language, wrong tool for this job. You'd spend weeks on GUI plumbing that Swift gives you for free.

#### Go
**Pros:**
- Simple language, single binary
- Fast compilation

**Cons:**
- No viable macOS GUI story
- Options are all bad:
  - **Fyne:** Cross-platform, not native
  - **Wails:** Web-based UI
  - **CGo + Objective-C:** Painful interop
- Not the right tool for GUI apps

**Verdict:** Don't.

### Recommendation: Swift + SwiftUI (AppKit as needed)

Swift wins not because it's the "best" language, but because:

1. **It's what macOS is designed for.** You're not fighting the platform.
2. **Xcode handles the hard parts.** Signing, notarization, universal binaries, .app bundles—all built-in.
3. **SwiftUI is actually good now.** For a three-pane app with a list, editor, and search box, it's ideal.
4. **FSEvents, Spotlight APIs, system integration**—all documented primarily for Swift.
5. **Homebrew Cask expects a standard .app.** Swift/Xcode produces exactly this.

If this were a CLI tool or a cross-platform app, Rust would be compelling. But for "native macOS GUI app with zero friction distribution," Swift is the pragmatic choice.

### If Swift Becomes Painful

Escape hatches if SwiftUI frustrates you:

- **Drop to AppKit** for specific views (they interop cleanly)
- **Objective-C files** can be mixed into Swift projects if needed
- **Swift Package Manager** for any dependencies (though we want near-zero)

### Prototype Findings (January 2026)

Validated through hands-on prototype testing:

**SwiftUI Works Well For:**
- Three-pane layout (search, list, editor)
- `List` component feels responsive (tested with 10 items, need to verify at 1000+)
- `TextEditor` feels responsive for basic editing
- `@FocusState` enables programmatic focus management
- `.onKeyPress()` (macOS 14+) handles custom keyboard navigation

**May Need AppKit For:**
- Global hotkey (summon app from anywhere) - requires CGEvent/AppKit
- NSTextView if `TextEditor` struggles at scale with large files
- Complex keyboard interception edge cases

**Known Build Issues:**
- Metal shader cache can lock during build (`flock` errors)
- Fix: Delete `/var/folders/.../com.apple.metal/` cache and DerivedData
- Kill stuck `ibtoold` processes if needed

### Final Stack

| Component | Choice | Rationale |
|-----------|--------|-----------|
| Language | Swift | Native, blessed toolchain, minimal friction |
| UI Framework | SwiftUI + AppKit fallbacks | SwiftUI for speed, AppKit for edge cases |
| Platform | **macOS 14+ (Sonoma)** | Required for `.onKeyPress` support (no beep navigation) |
| Dependencies | Zero external | System frameworks only |
| Binary | Universal (arm64 + x86_64) | No Rosetta required |
| Build System | Xcode + xcodebuild | Handles signing, notarization, bundling |

---

## Distribution Strategy

### Target: Zero-Friction Installation

Users should be able to install this in under 30 seconds with no confusion.

### Primary Distribution Channels

| Channel | Priority | Timeline | Effort |
|---------|----------|----------|--------|
| **Homebrew Cask** | High | MVP | Medium |
| **Direct DMG download** | High | MVP | Low |
| **Mac App Store** | Low | Post-validation | High |

### Homebrew Cask (Primary)

```bash
brew install --cask alt-nv
```

**Requirements:**
- Stable versioned releases (semantic versioning)
- DMG or ZIP hosted at predictable URL (GitHub Releases)
- Code signing with Developer ID
- Notarization (required for macOS 10.15+)

### Direct Download (One-Click Installer)

Standard macOS drag-to-install:
1. User downloads DMG
2. Opens DMG, drags app to Applications
3. Done

**Requirements:**
- Code signed with Developer ID
- Notarized with Apple
- DMG with Applications folder alias

### Architectural Implications

Distribution goals constrain technical choices:

| Requirement | Implication |
|-------------|-------------|
| **Homebrew Cask compatible** | Self-contained .app bundle, no post-install scripts |
| **No external dependencies** | Pure Swift/system frameworks. No Python, Node, or runtime requirements. |
| **Single binary** | Everything bundled in .app. No helper tools to install separately. |
| **Gatekeeper friendly** | Code signing + notarization mandatory, even for dev builds. |
| **Universal binary** | Build for arm64 + x86_64. No Rosetta dependency. |

### Apple Developer Account

**When to get it:** Only when you're ready to distribute to others (Phase 4).

- Developer ID Application certificate (code signing)
- Notarization capability (malware scan)
- Cost: $99/year

For personal use during development, a free Apple ID is sufficient. Don't spend money until you've validated the app is worth maintaining.

### CI/CD Pipeline (Set Up in Phase 2)

Automate releases to avoid tedious manual steps:

```
git tag v0.1.0
    → GitHub Actions builds universal binary
    → Signs with Developer ID  
    → Notarizes with Apple (staples ticket to app)
    → Creates DMG with drag-to-install layout
    → Uploads to GitHub Releases
    → (Optional) PRs to homebrew-cask repo
```

**Tools:** `create-dmg`, `xcrun notarytool`, GitHub Actions

### Mac App Store (Deferred)

**Pros:** Discoverability, auto-updates, user trust

**Cons:**
- Sandboxing may conflict with "point at any folder" (needs entitlement)
- Review delays
- Additional signing complexity

**Decision:** Defer until Homebrew + direct download are working and the app is validated through daily use. MAS is for broader reach, not early adopters.

---

## Success Metrics

| Metric | Target |
|--------|--------|
| Daily use | Yes, every day |
| Trust with important text | Would be upset if data lost |
| Faster than alternatives | Sub-100ms for any operation |
| Replaced temp text files | Haven't created one in 2+ weeks |

If yes to all four, it's working.

---

## Design Decisions

### Unified Search/Create Bar (NV-Style)

The search bar and file creation are unified. You type, it filters. If nothing matches and you keep typing, hit Enter to create a new file. This is NV's killer feature—the "is it searching or creating?" ambiguity disappears once learned, and it eliminates a decision point.

### File Naming

First line becomes the filename automatically. No prompts, no friction. If the first line is empty or unsuitable, generate a timestamp-based name.

### Nested Folder Display

Flat list by default, with relative path shown as subtle secondary text:

```
note-title
  projects/work/
```

Best of both worlds: fast scanning, context preserved.

### External Edit Handling

Auto-reload when external changes detected, with a subtle visual indicator (title flash or "updated externally" toast). Respects the "filesystem is truth" principle without creating friction.

---

## Data Integrity (Non-Negotiable)

**The app must never silently lose data.**

This is the cardinal rule. Every other design decision is subordinate to this.

### Auto-Save Failure Handling

If auto-save fails for any reason (disk full, permissions, sync conflict, filesystem error):

1. **Stop immediately**—do not continue as if nothing happened
2. **Scream loudly**—modal alert, not a subtle notification
3. **Block further editing** until resolved—prevent accumulating unsaved changes
4. **Show exactly what failed** and why (file path, error message)
5. **Offer clear recovery options:**
   - Retry save
   - Save to alternate location
   - Copy content to clipboard
   - Show file in Finder

The user should never close the app wondering "did that save?"

### File Watching

- Monitor for external changes via FSEvents
- If conflict detected (file changed while buffer dirty), prompt before overwriting
- Never auto-reload over unsaved local changes

### Defensive Practices

- Write to temp file, then atomic rename (never corrupt existing file)
- Verify write succeeded before clearing dirty flag
- Keep previous version until new version confirmed on disk

---

## Open Questions

---

## Competitive Landscape

| Tool | Status | Gap |
|------|--------|-----|
| Notational Velocity / NVAlt | Not updated 8–15 years, missing modern UI features | 
| Obsidian | Active | Closed source, too complex |
| Logseq | Active | Overwhelming, structure-first |
| Drafts | Active | iOS-first, sync required |
| Bear, Notion, etc. | Active | Way too much |
| Org-mode in Emacs | Active | Great for processing, terrible for quick capture |
| Plain text + Spotlight | Works | Missing the UI layer |
| fsnotes | The "NV Successor": Retains basic workflow, but adds complexity. |


---

*This is a living document. Like the app itself, it should remain simple and focused. If this document gets too long, we've lost the plot.*

# neonv Edge Cases and Limitations

This document covers edge cases, error handling scenarios, and known limitations discovered during neonv development and daily use.

---

## Filename Handling

### Unicode and Special Characters

**Current Behavior:**
- The `sanitizeFileName()` function strips all non-ASCII characters, including emoji and non-Latin scripts
- Only `[a-z0-9-]` characters are preserved in generated filenames
- Spaces become hyphens; all other characters are removed

**Example:**
| User Input | Generated Filename |
|------------|-------------------|
| `Meeting Notes 📝` | `meeting-notes.md` |
| `日本語メモ` | `untitled-20260129-143022.md` |
| `Café ideas` | `caf-ideas.md` |
| `Project: Alpha/Beta` | `project-alphabeta.md` |

**Implications:**
- Internationalized titles lose their content in filenames
- Files can still have Unicode content; only the filename is affected
- Existing files with Unicode filenames display and edit correctly

**Future Consideration:** Allow Unicode in filenames while escaping only filesystem-unsafe characters (`/`, `\`, `:`, `*`, `?`, `"`, `<`, `>`, `|`, NUL).

### Very Long Filenames

**Current Behavior:**
- Filename component truncated to 100 characters
- macOS HFS+/APFS limit is 255 bytes (UTF-8), so multibyte characters could theoretically exceed this, but current ASCII-only policy prevents issues

**Edge Case:** A title consisting entirely of stripped characters (e.g., `🎉🎊🎈`) results in a timestamp-based fallback filename.

### Filename Collisions

**Current Behavior:**
- No collision detection when creating files
- Creating two notes with the same title will overwrite the first

**Workaround:** The timestamp-based untitled fallback prevents most collisions in practice.

---

## Large File Handling

### File Size Behavior

| File Size | Behavior |
|-----------|----------|
| < 1 MB | Loads instantly, edits responsively |
| 1-10 MB | Loads quickly, minor lag on very rapid typing |
| 10-50 MB | Noticeable load time (1-3 seconds), typing may stutter |
| 50-100 MB | Load time 5-10+ seconds, editor becomes sluggish |
| > 100 MB | Not recommended; may cause memory pressure |

**Technical Details:**
- Content preview reads only first 2048 bytes (`readContentPreview`)
- First line (title) reads only first 256 bytes (`readFirstLine`)
- Full file is loaded into memory when selected for editing
- No lazy loading or virtualized rendering

**Recommendations:**
- For files > 10 MB, use a dedicated text editor
- neonv is optimized for quick notes, not log files

### Memory Pressure

**Behavior:** 
- No explicit memory limit
- Very large files may trigger macOS memory warnings
- App does not proactively refuse to open large files

---

## File Extensions

### Supported Extensions

The app recognizes these extensions (case-insensitive):
- `.txt`
- `.md`
- `.markdown`
- `.org`
- `.text`

**Behavior:**
- Files with other extensions are ignored during folder enumeration
- They won't appear in the note list
- Hardcoded in `NoteStore.swift` and `FileWatcher.swift`

### Unusual Extensions

| Scenario | Behavior |
|----------|----------|
| `.TXT` (uppercase) | Recognized (case-insensitive matching) |
| `.txt.bak` | Ignored (extension is `.bak`) |
| No extension | Ignored |
| `.org~` (Emacs backup) | Ignored |
| `.#file.md` (Emacs lock) | Ignored (hidden file) |

---

## Symlinks and Special Files

### Symbolic Links

**Current Behavior:**
- Symlinks to files: Followed and indexed if target has valid extension
- Symlinks to directories: Followed during enumeration
- Broken symlinks: Silently skipped (no error shown)

**Gotcha:** Editing a symlinked file edits the target, not the link itself.

### Hard Links

**Behavior:** Both hardlinked paths appear as separate files if within the notes folder.

### Device Files and FIFOs

**Behavior:** 
- Filtered out by `.isRegularFile` check
- Never appear in note list

---

## Network Drives and Mounted Volumes

### SMB/AFP/NFS Network Shares

**Known Behaviors:**
- FSEvents may not work reliably on network volumes
- File watching may miss external changes
- Latency can cause save operations to feel slow
- Atomic write (temp file + rename) generally works, but some NAS devices may have issues

**Recommendations:**
- For network drives, manually refresh (`Cmd+R` not implemented—close and reopen folder)
- Expect file watching to be less reliable
- Save operations may take longer

### External USB/Thunderbolt Drives

**Behavior:** Work normally; FSEvents functions correctly on local external drives.

### iCloud Drive

**Special Handling:**
- iCloud placeholder files (not downloaded) have valid paths but may fail to read
- Content reads return empty string for not-yet-downloaded files
- User must ensure files are downloaded locally

**Sync Conflicts:**
- iCloud may create `filename (conflicted copy).md`
- neonv will show both files in the list
- No automatic conflict resolution

---

## Cloud Sync Conflicts

### General Conflict Pattern

When the same file is edited on two devices before sync completes:

1. First sync wins, second creates a conflict copy
2. Conflict copy appears as a separate note
3. User must manually merge and delete

### Dropbox

- Creates `filename (conflicted copy 2026-01-29).md`
- Appears as a separate note in neonv

### iCloud

- Creates `filename (conflicted copy from Device).md`
- Same behavior as Dropbox

### OneDrive

- Uses similar conflict file naming
- Same behavior

### Syncthing / Resilio Sync

- Creates `filename.sync-conflict-20260129-143022-DEVICE.md`
- Extension may not match, causing file to be ignored
- Workaround: Rename conflict file to restore `.md` extension

---

## Multi-App File Access

### File Open in Multiple Apps

**Scenario:** Same file open in neonv and another editor (VS Code, Vim, etc.)

**Behavior:**
- neonv detects external changes via FSEvents
- If neonv has unsaved changes: Shows conflict dialog ("Keep Mine" / "Use External")
- If neonv has no unsaved changes: Auto-reloads with toast notification

### Atomic Save Detection

**How it works:**
- Many editors (Vim, VS Code) use atomic saves (write temp, rename)
- FSEvents may report as "create" instead of "modify"
- neonv handles both events identically for tracked files

### Lock Files

**Vim `.swp` files:** Ignored (hidden file, wrong extension)
**Emacs `#lockfile#`:** Ignored (hidden file)
**VSCode:** No lock files created

---

## Error Handling

### Save Failures

When save fails (disk full, permissions, network error):

1. **Modal alert** appears immediately (not silent)
2. **Editing is blocked** to prevent accumulating unsaved changes
3. **Options provided:**
   - Retry: Attempt save again
   - Copy to Clipboard: Rescue content
   - Save Elsewhere: Save to alternate location
   - Show in Finder: Navigate to file location

### Read Failures

**Behavior:**
- Failed file reads return empty string
- No explicit error shown to user
- File appears in list but content is blank

**Future Improvement:** Show explicit error state for unreadable files.

### Permission Errors

**Security-scoped bookmarks:**
- Folder access preserved across app restarts
- If bookmark becomes stale, user must re-select folder

**File-level permissions:**
- Read-only files can be opened but save will fail
- Error dialog explains permission issue

---

## Platform-Specific Behaviors

### macOS Version Requirements

- **Minimum:** macOS 14.0 (Sonoma)
- **Reason:** `.onKeyPress()` API required for keyboard navigation

### Apple Silicon vs Intel

- Universal binary supports both architectures
- No known behavioral differences

### Sandbox Considerations (Future)

If distributed via Mac App Store with sandbox:
- User must grant folder access via open panel
- Security-scoped bookmarks required (already implemented)
- Network drives may require additional entitlements

---

## Known Limitations

### No File Locking
neonv does not lock files. Multiple apps can edit simultaneously, risking conflicts.

### No Version History
Auto-save overwrites the file directly. Use Time Machine or git for versioning.

### No Encryption
Files stored as plain text. Use macOS FileVault or encrypted volume for sensitive content.

### No Trash Integration
Deleted files are permanently removed via `FileManager.removeItem()`, not moved to Trash.

### 100-Character Filename Limit
Generated filenames truncated at 100 characters (filesystem limit is 255 bytes).

### ASCII-Only Generated Filenames
Unicode titles create ASCII-only filenames, losing non-Latin information.

---

## Testing Edge Cases

To verify edge case handling:

### Test Unicode Filename
1. Create note with title `テスト 📝`
2. Verify filename is `untitled-TIMESTAMP.md`
3. Verify content is preserved correctly

### Test Large File
1. Create a 20MB text file externally
2. Open folder containing it in neonv
3. Select the file; verify it loads (with delay)
4. Edit and save; verify save completes

### Test External Modification
1. Select a note in neonv
2. Edit same file in another app
3. Verify neonv shows toast or conflict dialog

### Test Network Volume
1. Select a folder on a network share
2. Create and edit notes
3. Verify saves complete (may be slower)
4. Note: File watching may be unreliable

---

*Last updated: January 2026*

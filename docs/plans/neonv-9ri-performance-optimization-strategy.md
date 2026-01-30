# Performance Optimization Strategy for Instant Startup

**Task:** neonv-9ri  
**Date:** 2026-01-30  
**Target:** <200ms startup to first interaction

---

## Executive Summary

NeoNV's core value proposition is **instant capture and retrieval**. The app must feel like an extension of thought—any perceptible delay breaks the flow. This document outlines the technical strategy to achieve sub-200ms startup time and maintain <50ms responsiveness for all user actions.

---

## Current Architecture Analysis

### Startup Sequence (Current)

```
App Launch
    ├─ NeoNVApp.init()
    │   └─ @StateObject NoteStore()
    │       └─ loadSavedFolder()
    │           ├─ Resolve security-scoped bookmark
    │           └─ discoverFiles() [BLOCKING PATH]
    │               ├─ File enumeration
    │               ├─ Read first line of each file
    │               └─ Sort by modification date
    ├─ WindowGroup body evaluation
    │   └─ ContentView(noteStore:)
    │       └─ View hierarchy construction
    └─ First frame rendered
```

### Identified Bottlenecks

| Component | Estimated Time | Severity | Notes |
|-----------|---------------|----------|-------|
| `discoverFiles()` | 50-500ms+ | **HIGH** | Scales with file count; reads disk |
| `readFirstLine()` per file | ~1-2ms each | MEDIUM | 1000 files = 1-2 seconds |
| `readContentPreview()` | ~1-3ms each | MEDIUM | Reads 2KB per file |
| Security-scoped bookmark | ~10-20ms | LOW | Required, can't avoid |
| View hierarchy construction | ~10-30ms | LOW | SwiftUI is efficient |
| Settings singleton init | ~1-5ms | LOW | UserDefaults reads |

### File Discovery Profiling

Current `enumerateNotes()` performs these operations per file:
1. Path extension check
2. `resourceValues(forKeys:)` system call
3. `FileHandle` open, read 256 bytes, close (first line)
4. `FileHandle` open, read 2048 bytes, close (preview)
5. String processing

For a 1,000-file folder, this means ~4,000 file I/O operations before the UI is ready.

---

## Optimization Strategy

### Phase 1: Deferred Loading (Immediate Win)

**Goal:** Show UI within 50ms, load content progressively.

#### 1.1 Skeleton UI First

```swift
@main
struct NeoNVApp: App {
    @StateObject private var noteStore = NoteStore()

    var body: some Scene {
        WindowGroup {
            ContentView(noteStore: noteStore)
        }
    }
}
```

Change `NoteStore.init()` to NOT call `loadSavedFolder()` synchronously:

```swift
init() {
    // Don't load here - let view trigger it
}

func loadSavedFolderAsync() async {
    guard !hasLoaded else { return }
    hasLoaded = true
    // ... existing loadSavedFolder logic
}
```

ContentView calls this in `.task {}`:

```swift
.task {
    await noteStore.loadSavedFolderAsync()
}
```

**Expected gain:** UI visible in <50ms, file loading happens in background.

#### 1.2 Progressive File Loading

Instead of loading all files before showing the list, stream results:

```swift
func discoverFiles() async {
    isLoading = true
    
    // Clear and start fresh
    notes = []
    
    let stream = await enumerateNotesStream(in: folderURL)
    for await batch in stream {
        notes.append(contentsOf: batch)
        notes.sort { $0.modificationDate > $1.modificationDate }
    }
    
    isLoading = false
}
```

Use `AsyncStream` to yield files in batches of 50-100:

```swift
static func enumerateNotesStream(in folderURL: URL, batchSize: Int = 50) -> AsyncStream<[NoteFile]> {
    AsyncStream { continuation in
        Task.detached(priority: .userInitiated) {
            // ... enumerate files
            var batch: [NoteFile] = []
            for file in enumerator {
                batch.append(processFile(file))
                if batch.count >= batchSize {
                    continuation.yield(batch)
                    batch = []
                }
            }
            if !batch.isEmpty {
                continuation.yield(batch)
            }
            continuation.finish()
        }
    }
}
```

**Expected gain:** First 50 notes visible within 100ms.

---

### Phase 2: Metadata Caching

**Goal:** Skip disk I/O on subsequent launches.

#### 2.1 Lightweight Cache File

Store a JSON/plist cache of file metadata:

```swift
struct CachedNote: Codable {
    let relativePath: String
    let modificationDate: Date
    let title: String
    let contentPreview: String
}
```

Cache location: `~/Library/Caches/com.neonv/notes-index.json`

#### 2.2 Cache Validation Strategy

On startup:
1. Load cache file (fast: single read, JSON decode)
2. Display cached list immediately
3. In background: validate cache against filesystem
4. Update any stale entries
5. FileWatcher handles ongoing changes

Validation approach:
```swift
func validateCache(against folderURL: URL) async {
    let fileManager = FileManager.default
    
    // Quick scan: just get mod dates, no content read
    for note in cachedNotes {
        let url = folderURL.appendingPathComponent(note.relativePath)
        if let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
           attrs.contentModificationDate == note.modificationDate {
            // Cache is valid, skip
            continue
        }
        // Stale: re-read and update
        await refreshNote(at: url)
    }
    
    // Detect new files
    await scanForNewFiles(in: folderURL)
}
```

**Expected gain:** ~10-30ms startup for cached folders.

#### 2.3 Cache Invalidation Events

Invalidate on:
- App version change (cache format may differ)
- Folder URL change
- "Reload" user action
- FileWatcher events (incremental updates)

---

### Phase 3: Lazy Content Loading

**Goal:** Only read file content when needed.

#### 3.1 Deferred Preview Loading

Current `readContentPreview()` reads 2KB per file. For 1000 files, that's 2MB of I/O at startup.

**Optimization:** Don't read content preview until the file is scrolled into view.

```swift
struct NoteFile {
    // ...
    var contentPreview: String?  // nil = not loaded yet
    
    var needsContentLoad: Bool { contentPreview == nil }
}
```

In list view, use `onAppear` to trigger load:

```swift
ForEach(notes) { note in
    NoteRow(note: note)
        .onAppear {
            if note.needsContentLoad {
                Task {
                    await noteStore.loadContentPreview(for: note.id)
                }
            }
        }
}
```

**Expected gain:** Skip 2MB+ of I/O at startup.

#### 3.2 First Line Optimization

For display titles, we only need the first ~100 chars. Current implementation reads 256 bytes which is reasonable, but we can batch these reads.

Consider: for large folders, skip first-line read entirely at startup. Use filename as temporary title, load real titles in background.

---

### Phase 4: AppDelegate Optimization

**Goal:** Minimize work before first frame.

#### 4.1 Audit Init-Time Work

Current `AppDelegate`:
- Sets `hasUnsavedChanges` flag
- No heavy operations ✓

Current `AppSettings.shared`:
- Reads 4 UserDefaults keys
- Acceptable, but ensure it's lazy

**Recommendation:** `AppSettings.shared` is fine as-is (singleton pattern is already lazy).

#### 4.2 Defer Non-Critical Setup

Delay these until after first frame:
- FileWatcher start (wait until files loaded)
- Notification observer setup (can be in `.task {}`)

---

### Phase 5: Search Optimization

**Goal:** Maintain <10ms search latency at scale.

#### 5.1 Current Implementation

Already good:
- Pre-computed lowercase strings for matching
- Simple `contains()` check
- Debounced input (50ms)

#### 5.2 Scaling Considerations

For 10,000+ notes, consider:
1. **Suffix array or trie** for prefix matching
2. **Inverted index** for word-based search
3. **Fuzzy matching** with Levenshtein distance (stretch goal)

For MVP, the current linear scan is acceptable. At 10,000 notes with 100-char titles:
- ~1MB of string data
- Linear scan: ~1-5ms on M1

**Recommendation:** Defer advanced search indexing until user feedback indicates it's needed.

---

## Performance Measurement Methodology

### Metrics to Track

| Metric | Target | Measurement Point |
|--------|--------|-------------------|
| Time to First Frame | <50ms | First `onAppear` callback |
| Time to Interactive | <200ms | Search bar accepts input |
| Time to Full Load | <2s | All notes visible and searchable |
| Search Latency | <10ms | Key press to filter update |
| Note Switch Latency | <50ms | Selection change to editor populated |
| Auto-Save Latency | <100ms | Edit to disk write complete |

### Instrumentation Approach

#### 1. Signposts for Instruments

```swift
import os.signpost

let perfLog = OSLog(subsystem: "com.neonv", category: "performance")

func discoverFiles() async {
    os_signpost(.begin, log: perfLog, name: "discoverFiles")
    defer { os_signpost(.end, log: perfLog, name: "discoverFiles") }
    // ...
}
```

#### 2. Console Logging (Development)

```swift
#if DEBUG
struct PerfTimer {
    let name: String
    let start = CFAbsoluteTimeGetCurrent()
    
    func mark(_ checkpoint: String) {
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print("⏱ \(name) - \(checkpoint): \(String(format: "%.1f", elapsed))ms")
    }
}
#endif
```

#### 3. Xcode Instruments Workflow

1. Profile with **Time Profiler**
2. Focus on main thread hangs
3. Look for:
   - Synchronous file I/O
   - Large allocations
   - Lock contention

---

## Implementation Timeline

### Sprint 1: Quick Wins (1-2 days)
- [ ] Defer `loadSavedFolder()` to `.task {}`
- [ ] Add loading state to show skeleton UI immediately
- [ ] Add basic performance logging

### Sprint 2: Progressive Loading (2-3 days)
- [ ] Implement `AsyncStream`-based file enumeration
- [ ] Batch processing (50 files at a time)
- [ ] Update UI progressively

### Sprint 3: Caching (3-4 days)
- [ ] Design cache format (Codable struct)
- [ ] Implement cache read/write
- [ ] Background validation
- [ ] Handle cache invalidation

### Sprint 4: Polish (1-2 days)
- [ ] Lazy content preview loading
- [ ] Signpost instrumentation
- [ ] Performance regression tests (manual checklist)

---

## Trade-offs and Risks

### Trade-off: Cache Complexity vs. Speed

**Pro:** Cached startup is dramatically faster (~10ms vs ~500ms)  
**Con:** Cache invalidation is hard; stale data is possible  
**Mitigation:** Always validate in background; cache is optimization, not source of truth

### Trade-off: Progressive Loading vs. Completeness

**Pro:** User sees content faster  
**Con:** Search results incomplete until fully loaded  
**Mitigation:** Show "Loading..." indicator; disable search until load complete OR accept partial results

### Risk: Large Folders

A user with 50,000+ files could still experience slow startup.

**Mitigation:**
1. Show warning for very large folders
2. Consider folder-based lazy loading (only scan active subdirectory)
3. Document recommended folder size (<10,000 files)

### Risk: Sync Conflicts with Cache

iCloud/Dropbox sync could modify files while cache is stale.

**Mitigation:** FileWatcher + background validation handles this. Cache is never authoritative.

---

## Success Criteria

| Criteria | Measurement |
|----------|-------------|
| Cold start <200ms | Instruments profiling with empty caches |
| Warm start <50ms | Instruments profiling with valid cache |
| 1000-file folder loads in <1s | Manual timing with test folder |
| No visible jank during load | 60fps maintained per Instruments |
| Search remains responsive during load | User testing |

---

## Appendix: File Counts in Real Workflows

| Use Case | Expected Files | Notes |
|----------|----------------|-------|
| Personal notes | 100-500 | Most common |
| Developer scratch | 200-1000 | Code snippets, todos |
| Zettelkasten | 1000-5000 | Daily notes over years |
| Documentation | 5000+ | Edge case |

Optimize for the 90th percentile: 1000-file folder should feel instant.

---

## References

- [Apple: Improving App Launch Time](https://developer.apple.com/documentation/xcode/improving-app-launch-time)
- [WWDC 2022: App Startup Time](https://developer.apple.com/videos/play/wwdc2022/110363/)
- [Swift Async Sequences](https://developer.apple.com/documentation/swift/asyncsequence)

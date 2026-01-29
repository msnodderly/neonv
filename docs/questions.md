# Architectural Questions

## Performance Optimization Strategy

**Related Issues:** neonv-9ri, neonv-c7q
**Status:** 🟡 Needs decision

### Measurement Approach for Startup Time

What constitutes "startup time" for measurement purposes?

Options:
1. App launch to first keystroke accepted (current description)
2. App launch to full UI rendered and interactive
3. App launch to file list loaded
4. App launch to first file editable

Considerations:
- First keystroke focuses on user action readiness
- Full UI rendered includes background operations
- File list loaded depends on directory size
- Different measurement methods yield different optimization strategies

Recommendation: First keystroke accepted, but also track UI render time for comparison

### Lazy Loading vs Background Loading

How should we handle expensive startup operations?

Options:
1. Lazy load everything except essentials
2. Background load non-critical features after UI appears
3. Hybrid: essential UI fast, background processing with progress indicators

Considerations:
- User perception vs actual performance
- Feature availability vs startup speed
- Implementation complexity
- Resource usage patterns

Recommendation: Needs performance profiling first to identify bottlenecks

## Search Term Highlighting Implementation

**Related Issues:** neonv-3dd
**Status:** 🟡 Ready (but technical approach unclear)

### Highlighting Scope and Performance

What's the scope of search highlighting?

Options:
1. Highlight only in visible file list items
2. Highlight in loaded editor content only
3. Highlight in both file list and editor
4. Pre-render highlights for all search results

Considerations:
- Performance impact with large file lists
- Real-time highlighting vs batch processing
- Memory usage for maintaining highlight state
- User experience expectations

## Speech-to-Text Integration

**Related Issues:** neonv-zcx
**Status:** 🟢 Ready

### Integration Approach

Should we rely on system dictation or integrate with external services?

Options:
1. System dictation only (Fn-Fn key)
2. Superwhisper integration for advanced features
3. Both - system basic, Superwhisper optional
4. Custom speech recognition implementation

Considerations:
- System dictation works automatically with TextEditor
- Superwhisper offers better accuracy but requires external dependency
- Custom implementation is significant engineering effort
- User privacy and offline requirements

Recommendation: Verify system dictation works, document limitations, consider Superwhisper as optional enhancement

## Font Picker Implementation

**Related Issues:** neonv-38d
**Status:** 🟡 Needs decision

### Font Management Strategy

How should font preferences be stored and managed?

Options:
1. System font picker with custom fonts list
2. Simple dropdown with common fonts
3. Custom font selector with preview
4. Font family + size separate controls

Considerations:
- Font availability across macOS versions
- Performance impact of loading many fonts
- User preference complexity
- Compatibility with existing UI scaling

## Git Integration Approach

**Related Issues:** neonv-3n2
**Status:** 🔴 Blocking (needs architectural decision)

### Git Integration Scope

What level of Git integration should we provide?

Options:
1. Simple commit history view
2. Full git operations (commit, push, pull, branch)
3. Automatic commits on save
4. Git status indicators in file list
5. Diff viewer and conflict resolution

Considerations:
- Complexity vs value proposition
- Target user expertise level
- Integration with existing Git workflows
- Potential for repository corruption

Recommendation: Start with history view and status indicators, add operations based on user feedback

## Org-mode Support

**Related Issues:** neonv-5s6
**Status:** 🟢 Ready

### Org-mode Features Scope

What Org-mode features should we support in preview?

Options:
1. Basic headers and lists
2. Full spec (tables, links, timestamps, TODO keywords)
3. Custom subset focused on note-taking
4. Toggleable sections with folding

Considerations:
- Implementation complexity vs usage patterns
- Performance with large org files
- Compatibility with Emacs org-mode
- Maintenance burden

Recommendation: Basic headers, lists, and TODO keywords first, expand based on usage
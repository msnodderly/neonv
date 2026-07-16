import Darwin
import XCTest

/// End-to-end UI tests for NeoNV.
///
/// Generated fixtures are injected via
/// NEONV_TEST_NOTES_DIR so the user's real notes folder is never touched.
final class NeoNVUITests: XCTestCase {

    private static let noteCount = 500
    private static let thisFilePath = URL(fileURLWithPath: #filePath)

    var app: XCUIApplication!
    var fixturesURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        fixturesURL = try createFixtures(noteCount: Self.noteCount)
        for testArtifact in ["0420.md", "0420-immediate-note.md", "0137.md"] {
            try? FileManager.default.removeItem(
                at: fixturesURL.appendingPathComponent(testArtifact)
            )
        }

        app = XCUIApplication()
        app.launchEnvironment["NEONV_TEST_NOTES_DIR"] = fixturesURL.path
        app.launchArguments += ["-isSearchFieldHidden", "0"]
        app.launchArguments += ["-isFileListHidden", "0"]
        app.launchArguments += ["-defaultFileExtension", "md"]
        // Window/split state restored from a previous manual session would
        // override the defaults under test (e.g. list pane width).
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try super.tearDownWithError()
    }

    // MARK: - Functional tests

    /// Scroll through the file list until the last generated note is visible.
    func testScrollFileListWorkflow() {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "App window not found")
        XCTAssertTrue(waitForInitialListPopulation(timeout: 10), "Note list never populated")
        XCTAssertTrue(scrollToBottom(using: window, bottomTitle: Self.noteTitle(Self.noteCount)), "Failed to scroll to the end of the note list")
    }

    /// Selecting a note from the list loads the full file body in the editor.
    func testSelectingNoteLoadsEditorContent() {
        XCTAssertTrue(waitForInitialListPopulation(timeout: 10), "Note list never populated")

        // Narrow first so the target row is on screen regardless of sort order.
        let searchField = app.textFields["search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field not found")
        searchField.click()
        searchField.typeText("0137")

        let row = app.staticTexts[Self.noteTitle(137)]
        XCTAssertTrue(row.waitForExistence(timeout: 3), "Narrowed list missing target note")
        row.click()

        let editor = app.textViews["note-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3), "Editor not found")
        XCTAssertTrue(waitForEditor(editor, containing: "Line 2 for Note 0137."), "Editor did not load the selected note content")
    }

    /// Pressing Return creates from the search text even when partial matches exist.
    func testSearchReturnCreatesFromPartialMatch() {
        XCTAssertTrue(waitForInitialListPopulation(timeout: 10), "Note list never populated")

        app.typeKey("l", modifierFlags: .command)
        let searchField = app.textFields["search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field not found")

        let createdNoteURL = fixturesURL.appendingPathComponent("0420.md")
        try? FileManager.default.removeItem(at: createdNoteURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: createdNoteURL)
        }

        app.typeText("0420")

        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(
            waitForFile(at: createdNoteURL, containing: "0420\n\n"),
            "Return from search did not create 0420.md from the partial-match query"
        )

        let editor = app.textViews["note-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3), "Editor not found")
        XCTAssertTrue(
            waitForEditor(editor, containing: "0420\n\n"),
            "Editor did not open the newly created note"
        )
    }

    /// Return uses every character currently in the field without waiting for search debounce.
    func testImmediateSearchReturnUsesCurrentText() {
        XCTAssertTrue(waitForInitialListPopulation(timeout: 10), "Note list never populated")

        app.typeKey("l", modifierFlags: .command)
        let searchField = app.textFields["search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field not found")

        let createdNoteURL = fixturesURL.appendingPathComponent("0420-immediate-note.md")
        try? FileManager.default.removeItem(at: createdNoteURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: createdNoteURL)
        }

        app.typeText("0420 immediate note")
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(
            waitForFile(at: createdNoteURL, containing: "0420 immediate note\n\n"),
            "Immediate Return did not create from the complete current field value"
        )
    }

    /// An exact first-line title opens the existing note instead of creating a duplicate.
    func testSearchReturnOpensExactTitle() {
        XCTAssertTrue(waitForInitialListPopulation(timeout: 10), "Note list never populated")

        app.typeKey("l", modifierFlags: .command)
        let searchField = app.textFields["search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field not found")
        app.typeText("Note 0137")

        app.typeKey(.return, modifierFlags: [])

        let editor = app.textViews["note-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3), "Editor not found")
        XCTAssertTrue(
            waitForEditor(editor, containing: "Line 2 for Note 0137."),
            "Return from an exact title did not open the existing note"
        )
    }

    /// Moving into the result list keeps partial-match opening explicit and keyboard-driven.
    func testSearchResultNavigationOpensPartialMatch() {
        XCTAssertTrue(waitForInitialListPopulation(timeout: 10), "Note list never populated")

        app.typeKey("l", modifierFlags: .command)
        let searchField = app.textFields["search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field not found")

        let unexpectedNoteURL = fixturesURL.appendingPathComponent("0137.md")
        try? FileManager.default.removeItem(at: unexpectedNoteURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: unexpectedNoteURL)
        }

        app.typeText("0137")
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: unexpectedNoteURL.path),
            "Navigating into results unexpectedly created a note"
        )

        let editor = app.textViews["note-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3), "Editor not found")
        XCTAssertTrue(
            waitForEditor(editor, containing: "Line 2 for Note 0137."),
            "Return from the result list did not open the selected partial match"
        )
    }

    /// Cmd-N creates a new note and opens the editor ready for input.
    func testCreateNewNoteWorkflow() {
        let searchField = app.textFields["search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))

        app.typeKey("n", modifierFlags: .command)

        let editor = app.textViews["note-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3), "Editor not opened after Cmd-N")
        editor.typeText("Automated test note\nContent written by XCUITest.")
    }

    /// Typing in the search field narrows the list to matching notes only.
    func testSearchNarrowsListToMatches() {
        XCTAssertTrue(waitForInitialListPopulation(timeout: 10), "Note list never populated")

        let searchField = app.textFields["search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field not found")

        searchField.click()
        searchField.typeText("0420")

        let match = app.staticTexts[Self.noteTitle(420)]
        XCTAssertTrue(match.waitForExistence(timeout: 3), "Matching note missing from narrowed list")

        let nonMatch = app.staticTexts[Self.noteTitle(1)]
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline && nonMatch.exists {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertFalse(nonMatch.exists, "Non-matching note still visible after narrowing")

        takeScreenshot(named: "search-narrowed")
    }

    /// A search that matches deep in a note body recenters the row preview on
    /// the match (prefixed with an ellipsis) so the user can see why the note
    /// is in the results.
    func testBodyMatchShowsRecenteredSnippet() throws {
        // snippet-probe.md (generated with the fixtures) holds the only
        // occurrence of the term, deep enough that the row must recenter.
        let probeURL = fixturesURL.appendingPathComponent("snippet-probe.md")
        guard FileManager.default.fileExists(atPath: probeURL.path) else {
            throw FixtureGenerationError(message: """
            Missing snippet-probe.md in \(fixturesURL.path).
            Regenerate fixtures: scripts/generate-test-fixtures.sh \(fixturesURL.path)
            """)
        }

        XCTAssertTrue(waitForInitialListPopulation(timeout: 10), "Note list never populated")

        let searchField = app.textFields["search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field not found")
        searchField.click()
        searchField.typeText("xylophone")

        let probeTitle = app.staticTexts["Snippet Probe"]
        XCTAssertTrue(probeTitle.waitForExistence(timeout: 5), "Probe note not found by body search")

        // SwiftUI exposes these list texts through the AX value, not the label.
        let snippet = app.staticTexts.matching(
            NSPredicate(format: "value BEGINSWITH %@ AND value CONTAINS %@", "…", "xylophone")
        ).firstMatch
        XCTAssertTrue(snippet.waitForExistence(timeout: 3), "Row preview was not recentered on the body match")

        takeScreenshot(named: "body-match-snippet")
    }

    /// The file list pane defaults to 25% of the window width.
    func testListPaneDefaultWidthIsQuarterOfWindow() {
        XCTAssertTrue(waitForInitialListPopulation(timeout: 10), "Note list never populated")

        let window = app.windows.firstMatch
        let list = app.descendants(matching: .any).matching(identifier: "note-list").firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5), "Note list element not found")

        let windowWidth = window.frame.width
        let ratio = list.frame.width / windowWidth
        XCTAssertEqual(ratio, 0.25, accuracy: 0.04,
                       "List pane is \(list.frame.width)pt of \(windowWidth)pt (\(ratio)) — expected ~25%")

        takeScreenshot(named: "pane-width")
    }

    /// Cmd-Shift-B toggles the file list pane.
    func testToggleFileListShortcut() {
        XCTAssertTrue(waitForInitialListPopulation(timeout: 10), "Note list never populated")
        let list = app.descendants(matching: .any).matching(identifier: "note-list").firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5), "Note list not found")

        app.typeKey("b", modifierFlags: [.command, .shift])
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline && list.exists {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertFalse(list.exists, "File list still visible after Cmd-Shift-B")

        app.typeKey("b", modifierFlags: [.command, .shift])
        XCTAssertTrue(list.waitForExistence(timeout: 3), "File list did not come back after Cmd-Shift-B")
    }

    /// Closing the window quits the app (single-window semantics).
    func testCloseWindowQuitsApp() {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "App window not found")

        window.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5), "App did not quit after closing its window")
    }

    /// Once autosave finishes, Cmd-Q quits without an unsaved-changes prompt.
    func testQuitAfterAutosaveDoesNotWarn() {
        XCTAssertTrue(waitForInitialListPopulation(timeout: 10), "Note list never populated")

        let noteURL = fixturesURL.appendingPathComponent("note-0137.md")

        let searchField = app.textFields["search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field not found")
        searchField.click()
        searchField.typeText("0137")

        let row = app.staticTexts[Self.noteTitle(137)]
        XCTAssertTrue(row.waitForExistence(timeout: 3), "Narrowed list missing target note")
        row.click()

        let editor = app.textViews["note-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3), "Editor not found")
        let marker = "Autosave quit regression marker \(UUID().uuidString)"
        editor.click()
        editor.typeKey(.downArrow, modifierFlags: .command)
        editor.typeText("\n\(marker)")

        XCTAssertTrue(
            waitForFile(at: noteURL, containing: marker),
            "Edit did not autosave before quit"
        )
        RunLoop.current.run(until: Date().addingTimeInterval(1))

        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(
            app.wait(for: .notRunning, timeout: 5),
            "Cmd-Q showed an unsaved-changes prompt after autosave completed"
        )
    }

    /// Before autosave finishes, Cmd-Q warns instead of discarding the edit.
    func testQuitBeforeAutosaveWarns() {
        XCTAssertTrue(waitForInitialListPopulation(timeout: 10), "Note list never populated")

        let searchField = app.textFields["search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field not found")
        searchField.click()
        searchField.typeText("0137")

        let row = app.staticTexts[Self.noteTitle(137)]
        XCTAssertTrue(row.waitForExistence(timeout: 3), "Narrowed list missing target note")
        row.click()

        let editor = app.textViews["note-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3), "Editor not found")
        editor.click()
        editor.typeKey(.downArrow, modifierFlags: .command)
        editor.typeText("\nImmediate quit regression marker \(UUID().uuidString)")
        app.typeKey("q", modifierFlags: .command)

        let warning = app.staticTexts["Unsaved Changes"]
        XCTAssertTrue(
            warning.waitForExistence(timeout: 3),
            "Cmd-Q did not warn while an edit was still awaiting autosave"
        )
        app.dialogs.buttons["Cancel"].click()
    }

    /// Clearing the search scrolls the restored selection back into view.
    func testClearingSearchRevealsSelection() {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "App window not found")
        XCTAssertTrue(waitForInitialListPopulation(timeout: 10), "Note list never populated")

        // Manually select the oldest note (deepest row in the list).
        let list = app.descendants(matching: .any).matching(identifier: "note-list").firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5), "Note list not found")
        let oldest = app.staticTexts[Self.noteTitle(1)]
        XCTAssertTrue(scrollListUntilHittable(oldest, in: list), "Could not scroll to the oldest note")
        oldest.click()

        // Searching saves the manual selection; clearing restores it.
        let searchField = app.textFields["search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field not found")
        searchField.click()
        searchField.typeText("0500")
        XCTAssertTrue(app.staticTexts[Self.noteTitle(500)].waitForExistence(timeout: 3), "Search did not narrow")
        app.typeKey(.escape, modifierFlags: [])

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline && !oldest.isHittable {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(oldest.isHittable, "Cleared search did not reveal the selected note")
    }

    /// Multi-word search requires all terms anywhere (AND), not the phrase.
    func testMultiWordSearchRequiresAllTerms() {
        XCTAssertTrue(waitForInitialListPopulation(timeout: 10), "Note list never populated")

        let searchField = app.textFields["search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field not found")
        searchField.click()
        // "0042" (title/filename) and "line 3" (body) never form a phrase.
        searchField.typeText("0042 line 3")

        let match = app.staticTexts[Self.noteTitle(42)]
        XCTAssertTrue(match.waitForExistence(timeout: 3), "AND search missed the note containing all terms")

        let nonMatch = app.staticTexts[Self.noteTitle(41)]
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline && nonMatch.exists {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertFalse(nonMatch.exists, "AND search kept a note that lacks a term")
    }

    /// Search matches content past the 2 KB preview cap, and the row shows a
    /// recentered snippet for the deep match.
    func testSearchFindsMatchBeyondPreviewCap() throws {
        let probeURL = fixturesURL.appendingPathComponent("deep-probe.md")
        guard FileManager.default.fileExists(atPath: probeURL.path) else {
            throw FixtureGenerationError(message: """
            Missing deep-probe.md in \(fixturesURL.path).
            Regenerate fixtures: scripts/generate-test-fixtures.sh \(fixturesURL.path)
            """)
        }

        XCTAssertTrue(waitForInitialListPopulation(timeout: 10), "Note list never populated")

        let searchField = app.textFields["search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field not found")
        searchField.click()
        searchField.typeText("quetzalcoatl")

        XCTAssertTrue(app.staticTexts["Deep Probe"].waitForExistence(timeout: 3),
                      "Search did not find a match past the preview cap")

        let snippet = app.staticTexts.matching(
            NSPredicate(format: "value BEGINSWITH %@ AND value CONTAINS %@", "…", "quetzalcoatl")
        ).firstMatch
        XCTAssertTrue(snippet.waitForExistence(timeout: 3), "Deep match did not show a recentered snippet")
    }

    // MARK: - Exploratory UI exercise
    //
    // Drives the main UI surfaces end to end, attaching screenshots so a
    // reviewer can audit each state. Soft-fails (records issues) rather than
    // aborting, to maximize coverage per run.

    func testExerciseCoreSurfaces() {
        continueAfterFailure = true
        XCTAssertTrue(waitForInitialListPopulation(timeout: 10), "Note list never populated")
        let searchField = app.textFields["search-field"]

        XCTContext.runActivity(named: "Search, open exact title via Return") { _ in
            searchField.click()
            searchField.typeText("Note 0042")
            app.typeKey(.return, modifierFlags: [])
            let editor = app.textViews["note-editor"]
            XCTAssertTrue(editor.waitForExistence(timeout: 3), "Editor missing after search Return")
            XCTAssertTrue(waitForEditor(editor, containing: "Line 2 for Note 0042."), "Exact title did not open")
            takeScreenshot(named: "exercise-1-open-exact-title")
        }

        XCTContext.runActivity(named: "Preview toggle (Cmd-P) on and off") { _ in
            app.typeKey("p", modifierFlags: .command)
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            takeScreenshot(named: "exercise-2-preview-on")
            app.typeKey("p", modifierFlags: .command)
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        }

        XCTContext.runActivity(named: "Find in note (Cmd-F) opens find bar") { _ in
            app.typeKey("f", modifierFlags: .command)
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            takeScreenshot(named: "exercise-3-find-bar")
            app.typeKey(.escape, modifierFlags: [])
        }

        XCTContext.runActivity(named: "Toggle layout (Cmd-Shift-J) round trip") { _ in
            app.typeKey("j", modifierFlags: [.command, .shift])
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            takeScreenshot(named: "exercise-4-horizontal-layout")
            app.typeKey("j", modifierFlags: [.command, .shift])
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        }

        XCTContext.runActivity(named: "Hide and show search bar (Cmd-Shift-L)") { _ in
            app.typeKey("l", modifierFlags: [.command, .shift])
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            XCTAssertFalse(searchField.exists, "Search field still visible after hide")
            takeScreenshot(named: "exercise-5-search-hidden")
            app.typeKey("l", modifierFlags: [.command, .shift])
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            XCTAssertTrue(searchField.waitForExistence(timeout: 2), "Search field did not come back")
        }

        XCTContext.runActivity(named: "Keyboard flow: search -> list -> editor -> search") { _ in
            app.typeKey("l", modifierFlags: .command)
            searchField.typeText("Note 01")
            app.typeKey(.downArrow, modifierFlags: [])   // into list
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            app.typeKey(.downArrow, modifierFlags: [])   // next row
            app.typeKey(.return, modifierFlags: [])      // into editor
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            takeScreenshot(named: "exercise-6-keyboard-flow")
            app.typeKey("l", modifierFlags: .command)    // back to search
        }

        XCTContext.runActivity(named: "Navigation history back/forward (Cmd-[ / Cmd-])") { _ in
            app.typeKey(.escape, modifierFlags: [])
            app.typeKey("[", modifierFlags: .command)
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            app.typeKey("]", modifierFlags: .command)
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            takeScreenshot(named: "exercise-7-nav-history")
        }

        XCTContext.runActivity(named: "Rename via context menu") { _ in
            app.typeKey("l", modifierFlags: .command)
            searchField.typeText("0003")
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            let row = app.staticTexts[Self.noteTitle(3)].firstMatch
            if row.waitForExistence(timeout: 3) {
                row.rightClick()
                let renameItem = app.menuItems["Rename"]
                if renameItem.waitForExistence(timeout: 2) {
                    renameItem.click()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                    takeScreenshot(named: "exercise-8-rename-dialog")
                    // The dialog field is focused with the name pre-selected;
                    // type at the app level — the field isn't reliably
                    // addressable through the textFields query.
                    app.typeText("renamed-note-0003")
                    app.typeKey(.return, modifierFlags: [])
                    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                } else {
                    XCTFail("Rename menu item not found")
                }
            } else {
                XCTFail("Could not find note row for rename")
            }
        }

        XCTContext.runActivity(named: "Keyboard shortcuts sheet (Cmd-K)") { _ in
            app.typeKey("k", modifierFlags: .command)
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            takeScreenshot(named: "exercise-9-shortcuts-sheet")
            app.typeKey(.escape, modifierFlags: [])
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }

        takeScreenshot(named: "exercise-final-state")
    }

    private func takeScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Performance benchmark

    /// Full file-list scrolling workflow: start at top of list and scroll until
    /// the final note becomes visible.
    ///
    /// This is the primary metric consumed by autoresearch.sh.
    func testFullFileListScrollPerformance() {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "App window not found")
        // Generous: the first launch of a freshly built binary can take >10s
        // to draw (one-time macOS verification). Setup only — not measured.
        XCTAssertTrue(waitForInitialListPopulation(timeout: 30), "Note list never populated")

        let options = XCTMeasureOptions()
        options.iterationCount = 5
        // Required for the explicit startMeasuring/stopMeasuring calls below;
        // current XCTest asserts otherwise ("autoStop mode").
        options.invocationOptions = [.manuallyStart, .manuallyStop]

        measure(metrics: [XCTClockMetric()], options: options) {
            XCTAssertTrue(scrollToTop(using: window, topTitle: Self.noteTitle(1)), "Failed to reset list to the top")

            startMeasuring()
            XCTAssertTrue(scrollToBottom(using: window, bottomTitle: Self.noteTitle(Self.noteCount)), "Failed to reach the bottom of the note list")
            stopMeasuring()
        }
    }

    // MARK: - Scroll helpers

    private func waitForInitialListPopulation(timeout: TimeInterval) -> Bool {
        let firstTitle = Self.noteTitle(1)
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if app.staticTexts[firstTitle].exists { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return app.staticTexts[firstTitle].exists
    }

    private func scrollToTop(using window: XCUIElement, topTitle: String, maxAttempts: Int = 40) -> Bool {
        for _ in 0..<maxAttempts {
            if app.staticTexts[topTitle].exists { return true }
            dragDownInListPane(window: window)
        }
        return app.staticTexts[topTitle].exists
    }

    private func scrollToBottom(using window: XCUIElement, bottomTitle: String, maxAttempts: Int = 80) -> Bool {
        for _ in 0..<maxAttempts {
            if app.staticTexts[bottomTitle].exists { return true }
            dragUpInListPane(window: window)
        }
        return app.staticTexts[bottomTitle].exists
    }

    /// Scrolls the list until `element` is actually hittable. Two traps here:
    /// `exists` is the wrong signal (SwiftUI exposes off-screen rows to AX
    /// with infinite frames), and press-drag doesn't scroll macOS lists — it
    /// selects rows. Wheel-event scrolling via scroll(byDeltaX:deltaY:) is
    /// the primitive that actually moves the list.
    private func scrollListUntilHittable(_ element: XCUIElement, in list: XCUIElement, maxAttempts: Int = 60) -> Bool {
        for _ in 0..<maxAttempts {
            if element.isHittable { return true }
            list.scroll(byDeltaX: 0, deltaY: -3000)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return element.isHittable
    }

    private func dragUpInListPane(window: XCUIElement) {
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.85))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.15))
        start.press(forDuration: 0.01, thenDragTo: end)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    private func dragDownInListPane(window: XCUIElement) {
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.15))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.85))
        start.press(forDuration: 0.01, thenDragTo: end)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    private func waitForEditor(_ editor: XCUIElement, containing expectedText: String, timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let value = editor.value as? String, value.contains(expectedText) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return (editor.value as? String)?.contains(expectedText) == true
    }

    private func waitForFile(
        at url: URL,
        containing expectedText: String,
        timeout: TimeInterval = 5
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let content = try? String(contentsOf: url, encoding: .utf8),
               content.contains(expectedText) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return (try? String(contentsOf: url, encoding: .utf8))?.contains(expectedText) == true
    }

    // MARK: - Fixture helpers

    private func createFixtures(noteCount: Int) throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        let fixturesURL = environment["NEONV_TEST_NOTES_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? Self.defaultFixturesURL

        try requireGeneratedFixtures(at: fixturesURL, noteCount: noteCount)
        return fixturesURL
    }

    private func requireGeneratedFixtures(at fixturesURL: URL, noteCount: Int) throws {
        let firstNote = fixturesURL.appendingPathComponent("note-0001.md")
        let lastNote = fixturesURL.appendingPathComponent(String(format: "note-%04d.md", noteCount))

        if FileManager.default.fileExists(atPath: firstNote.path),
           FileManager.default.fileExists(atPath: lastNote.path) {
            return
        }

        throw FixtureGenerationError(message: """
        Missing generated UI test fixtures in \(fixturesURL.path).
        Run: scripts/generate-test-fixtures.sh \(fixturesURL.path) \(noteCount)
        """)
    }

    private static func noteTitle(_ index: Int) -> String {
        String(format: "Note %04d", index)
    }

    private static var hostHomeDirectory: URL {
        if let passwd = getpwuid(getuid()), let home = passwd.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
        }

        return FileManager.default.homeDirectoryForCurrentUser
    }

    private static var defaultFixturesURL: URL {
        hostHomeDirectory
            .appendingPathComponent("Library/Containers/net.area51a.NeoNV/Data/tmp/NeoNVUITests-Fixtures", isDirectory: true)
    }
}

private struct FixtureGenerationError: Error, CustomStringConvertible {
    let message: String

    var description: String {
        message
    }
}

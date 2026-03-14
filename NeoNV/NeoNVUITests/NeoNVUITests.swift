import XCTest

/// End-to-end UI tests for NeoNV.
///
/// Fixtures are created in a temp directory each run and injected via
/// NEONV_TEST_NOTES_DIR so the user's real notes folder is never touched.
final class NeoNVUITests: XCTestCase {

    var app: XCUIApplication!
    var fixturesURL: URL!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false

        fixturesURL = createFixtures()

        app = XCUIApplication()
        app.launchEnvironment["NEONV_TEST_NOTES_DIR"] = fixturesURL.path
        // Override UserDefaults to ensure search field is visible during tests
        app.launchArguments += ["-isSearchFieldHidden", "0"]
        app.launch()
    }

    override func tearDown() {
        app.terminate()
        try? FileManager.default.removeItem(at: fixturesURL)
        super.tearDown()
    }

    // MARK: - Functional tests

    /// Search exact title → Return opens in editor → make an edit.
    func testSearchOpenEditWorkflow() {
        let searchField = app.textFields["search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field not found")

        // Type exact title match and press Return to select + focus editor
        searchField.click()
        searchField.typeText("Meeting Notes")
        searchField.typeKey(.return, modifierFlags: [])

        let editor = app.textViews["note-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3), "Editor not found")
        editor.typeText(" - edited by test")
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

    // MARK: - Performance benchmark

    /// Full edit workflow: search → open → type edit → wait for autosave.
    ///
    /// This is the primary metric consumed by autoresearch.sh.
    /// Uses exact title match + Return to select note and focus editor
    /// (pure keyboard flow — no mouse clicks on the note list).
    func testFullEditWorkflowPerformance() {
        let searchField = app.textFields["search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))

        let measuredNoteURL = fixturesURL.appendingPathComponent("meeting-notes.md")
        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(metrics: [XCTClockMetric()], options: options) {
            let baselineDate = (try? measuredNoteURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? .distantPast

            // 1. Type exact title and press Return to select + focus editor
            searchField.click()
            searchField.typeText("Meeting Notes")
            searchField.typeKey(.return, modifierFlags: [])

            // 2. Type a minimal edit to trigger autosave
            let editor = app.textViews["note-editor"]
            XCTAssertTrue(editor.waitForExistence(timeout: 1), "Editor not found")
            editor.typeText(" x")

            // 3. Wait only until the file is actually saved instead of always sleeping 500 ms
            XCTAssertTrue(waitForAutosave(of: measuredNoteURL, after: baselineDate), "Autosave did not complete in time")

            // Reset: clear search so next iteration starts clean
            searchField.click()
            searchField.typeKey("a", modifierFlags: .command)
            searchField.typeKey(.delete, modifierFlags: [])
        }
    }

    // MARK: - Fixture helpers

    /// Path to this source file at compile time — used to locate Fixtures/.
    private static let thisFilePath = URL(fileURLWithPath: #filePath)

    /// Copies the pre-generated 500-file fixture set to a temp directory.
    /// The fixtures live in NeoNVUITests/Fixtures/ (sibling to this test file).
    private func createFixtures() -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeoNVUITests-\(UUID().uuidString)")

        let fixturesSource = Self.thisFilePath
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")

        if FileManager.default.fileExists(atPath: fixturesSource.path) {
            try! FileManager.default.copyItem(at: fixturesSource, to: tmp)
        } else {
            // Fallback: create minimal fixtures inline
            try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            let notes: [(String, String)] = [
                ("meeting-notes.md", "# Meeting Notes\n\nAgenda items for the weekly sync."),
                ("todo.md", "# Todo\n\n- [ ] Item one\n- [ ] Item two"),
                ("journal.txt", "Journal entry.\n\nToday was productive.")
            ]
            for (name, content) in notes {
                try! content.write(to: tmp.appendingPathComponent(name), atomically: true, encoding: .utf8)
            }
        }
        return tmp
    }

    private func waitForAutosave(of url: URL, after baselineDate: Date, timeout: TimeInterval = 1.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let updatedDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               updatedDate > baselineDate {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        return false
    }
}

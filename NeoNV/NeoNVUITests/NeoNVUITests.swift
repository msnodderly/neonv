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
        app.launch()
    }

    override func tearDown() {
        app.terminate()
        try? FileManager.default.removeItem(at: fixturesURL)
        super.tearDown()
    }

    // MARK: - Functional tests

    /// Search → select first result → open in editor → make an edit.
    func testSearchOpenEditWorkflow() {
        let searchField = app.textFields["search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field not found")

        searchField.click()
        searchField.typeText("meeting")

        let noteList = app.lists["note-list"]
        XCTAssertTrue(noteList.waitForExistence(timeout: 3), "Note list not found")

        let firstNote = noteList.cells.firstMatch
        XCTAssertTrue(firstNote.waitForExistence(timeout: 3), "No notes matched search")
        firstNote.click()

        let editor = app.textViews["note-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3), "Editor not found")
        editor.click()
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
    /// Run this test directly to capture baseline timing:
    ///   xcodebuild test -scheme NeoNV -destination 'platform=macOS' \
    ///     -only-testing:NeoNVUITests/NeoNVUITests/testFullEditWorkflowPerformance
    ///
    /// The XCTest measure block prints: average: X.XXX s  (σ: ...)
    func testFullEditWorkflowPerformance() {
        let searchField = app.textFields["search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))

        measure(metrics: [XCTClockMetric()]) {
            // 1. Type search query
            searchField.click()
            searchField.typeText("meeting")

            // 2. Select first result
            let noteList = app.lists["note-list"]
            let firstNote = noteList.cells.firstMatch
            _ = firstNote.waitForExistence(timeout: 5)
            firstNote.click()

            // 3. Type a minimal edit to trigger autosave
            let editor = app.textViews["note-editor"]
            _ = editor.waitForExistence(timeout: 3)
            editor.click()
            editor.typeText(" x")

            // 4. Wait for the autosave debounce to fire (50 ms debounce + write)
            Thread.sleep(forTimeInterval: 0.5)

            // Reset: clear search so next iteration starts clean
            searchField.click()
            searchField.typeKey("a", modifierFlags: .command)
            searchField.typeKey(.delete, modifierFlags: [])
        }
    }

    // MARK: - Fixture helpers

    private func createFixtures() -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeoNVUITests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let notes: [(String, String)] = [
            ("meeting-notes.md", "# Meeting Notes\n\nAgenda items for the weekly sync."),
            ("todo.md", "# Todo\n\n- [ ] Item one\n- [ ] Item two"),
            ("journal.txt", "Journal entry.\n\nToday was productive.")
        ]
        for (name, content) in notes {
            try! content.write(to: tmp.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return tmp
    }
}

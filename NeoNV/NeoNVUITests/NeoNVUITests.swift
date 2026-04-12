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

        app = XCUIApplication()
        app.launchEnvironment["NEONV_TEST_NOTES_DIR"] = fixturesURL.path
        app.launchArguments += ["-isSearchFieldHidden", "0"]
        app.launchArguments += ["-isFileListHidden", "0"]
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

        app.staticTexts[Self.noteTitle(1)].click()

        let editor = app.textViews["note-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3), "Editor not found")
        XCTAssertTrue(waitForEditor(editor, containing: "Line 2 for Note 0001."), "Editor did not load the selected note content")
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

    /// Full file-list scrolling workflow: start at top of list and scroll until
    /// the final note becomes visible.
    ///
    /// This is the primary metric consumed by autoresearch.sh.
    func testFullFileListScrollPerformance() {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "App window not found")
        XCTAssertTrue(waitForInitialListPopulation(timeout: 10), "Note list never populated")

        let options = XCTMeasureOptions()
        options.iterationCount = 5

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

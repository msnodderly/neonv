import XCTest

/// End-to-end UI tests for NeoNV.
///
/// Fixtures are copied to a temp directory each run and injected via
/// NEONV_TEST_NOTES_DIR so the user's real notes folder is never touched.
final class NeoNVUITests: XCTestCase {

    private static let noteCount = 500
    private static let thisFilePath = URL(fileURLWithPath: #filePath)

    var app: XCUIApplication!
    var fixturesURL: URL!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false

        fixturesURL = createFixtures(noteCount: Self.noteCount)

        app = XCUIApplication()
        app.launchEnvironment["NEONV_TEST_NOTES_DIR"] = fixturesURL.path
        app.launchArguments += ["-isSearchFieldHidden", "0"]
        app.launch()
    }

    override func tearDown() {
        app.terminate()
        try? FileManager.default.removeItem(at: fixturesURL)
        super.tearDown()
    }

    // MARK: - Functional tests

    /// Scroll through the file list until the last generated note is visible.
    func testScrollFileListWorkflow() {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "App window not found")
        XCTAssertTrue(waitForInitialListPopulation(timeout: 10), "Note list never populated")
        XCTAssertTrue(scrollToBottom(using: window, bottomTitle: Self.noteTitle(Self.noteCount)), "Failed to scroll to the end of the note list")
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

    // MARK: - Fixture helpers

    private func createFixtures(noteCount: Int) -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeoNVUITests-\(UUID().uuidString)")

        let fixturesSource = Self.thisFilePath
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")

        if FileManager.default.fileExists(atPath: fixturesSource.path) {
            try! FileManager.default.copyItem(at: fixturesSource, to: tmp)
        } else {
            try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            for index in 1...noteCount {
                let name = String(format: "note-%04d.md", index)
                let title = Self.noteTitle(index)
                let content = "# \(title)\n\nLine 1 for \(title).\nLine 2 for \(title).\nLine 3 for \(title).\n"
                try! content.write(to: tmp.appendingPathComponent(name), atomically: true, encoding: .utf8)
            }
        }

        return tmp
    }

    private static func noteTitle(_ index: Int) -> String {
        String(format: "Note %04d", index)
    }
}

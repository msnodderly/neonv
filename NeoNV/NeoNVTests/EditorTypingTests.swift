import XCTest
import SwiftUI
@testable import NeoNV

final class WikiLinkParserTests: XCTestCase {
    func testUnclosedTargetOnlyReplacesTextBeforeCursor() throws {
        let text = "Notes\n[[pro unfinished text\nKeep this [[other]]" as NSString
        let cursor = text.range(of: " unfinished").location
        let context = try XCTUnwrap(WikiLinkParser.contextAtCursor(in: text, cursorLocation: cursor))

        XCTAssertEqual(context.query, "pro")
        XCTAssertEqual(context.replacementRange, text.range(of: "pro"))
        XCTAssertFalse(context.hasClosingBrackets)
    }

    func testClosedTargetReplacesWholeTargetButPreservesLabel() throws {
        let text = "Before [[project plan|My label]] after" as NSString
        let cursor = text.range(of: "project").location + 3
        let context = try XCTUnwrap(WikiLinkParser.contextAtCursor(in: text, cursorLocation: cursor))

        XCTAssertEqual(context.query, "pro")
        XCTAssertEqual(context.replacementRange, text.range(of: "project plan"))
        XCTAssertTrue(context.hasClosingBrackets)
        XCTAssertNil(WikiLinkParser.contextAtCursor(in: text, cursorLocation: text.range(of: "label").location))
        XCTAssertNil(WikiLinkParser.contextAtCursor(in: text, cursorLocation: text.length))
    }

    func testEarlierLineCannotStartCompletion() {
        for separator in ["\n", "\r\n", "\r", "\u{2028}", "\u{2029}"] {
            let text = "[[unfinished\(separator)ordinary text" as NSString
            XCTAssertNil(WikiLinkParser.contextAtCursor(in: text, cursorLocation: text.length))
        }
    }

    func testEmptyTargetAndCursorAtLineBoundaries() throws {
        let text = "previous\n[[\nnext" as NSString
        let cursor = text.range(of: "[[").location + 2
        let context = try XCTUnwrap(WikiLinkParser.contextAtCursor(in: text, cursorLocation: cursor))
        XCTAssertEqual(context.query, "")
        XCTAssertEqual(context.replacementRange, NSRange(location: cursor, length: 0))
        XCTAssertFalse(context.hasClosingBrackets)
        XCTAssertNil(WikiLinkParser.contextAtCursor(in: text, cursorLocation: cursor + 1))
        XCTAssertNil(WikiLinkParser.contextAtCursor(in: "", cursorLocation: 0))
    }

    func testUnicodeOffsetsAndLastTargetOnCurrentLine() throws {
        let text = "📝 [[earlier]]\r\n🧑🏽‍💻 [[done]] then [[café 📝]]" as NSString
        let cursor = text.range(of: "café 📝").location + ("café 📝" as NSString).length
        let context = try XCTUnwrap(WikiLinkParser.contextAtCursor(in: text, cursorLocation: cursor))
        XCTAssertEqual(context.query, "café 📝")
        XCTAssertEqual(context.replacementRange, text.range(of: "café 📝"))
        XCTAssertTrue(context.hasClosingBrackets)
    }

    func testCompletionLookupInLongNotePerformance() {
        let prefix = String(repeating: "A normal note line with some words and emoji 📝.\n", count: 50_000)
        let plainText = (prefix + "ordinary typing") as NSString
        let linkText = (prefix + "[[pro\nKeep this [[other]]") as NSString
        let cursor = (prefix as NSString).length + 5

        // Exercise both callbacks' common cases: ordinary typing and an open link
        // near the end of a multi-megabyte note. No disk or UI automation overhead.
        measure {
            for _ in 0..<100 {
                XCTAssertNil(WikiLinkParser.contextAtCursor(in: plainText, cursorLocation: plainText.length))
                let context = WikiLinkParser.contextAtCursor(in: linkText, cursorLocation: cursor)
                XCTAssertEqual(context?.query, "pro")
                XCTAssertEqual(context?.hasClosingBrackets, false)
            }
        }
    }
}

final class PlainTextEditorTests: XCTestCase {
    @MainActor
    func testLocalEditPublishesIndependentSnapshot() {
        var content = "Original 📝 text"
        var edits: [String] = []
        let coordinator = PlainTextEditor.Coordinator(
            text: Binding(get: { content }, set: { content = $0 }),
            cursorPosition: .constant(0), scrollFraction: .constant(0),
            resolveWikiLink: { .missing($0) }, wikiSuggestions: { _ in [] },
            wikiIndexVersion: 0, wikiAutocompleteEnabled: true,
            onTextChange: { edits.append($0) }
        )
        let textView = NSTextView()
        textView.string = "Edited 📝 text"
        coordinator.textView = textView
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        XCTAssertEqual(content, "Edited 📝 text")
        XCTAssertEqual(coordinator.lastSyncedText, content)

        // AppKit's next mutation must not mutate a previously published snapshot.
        textView.textStorage?.replaceCharacters(in: NSRange(location: 0, length: 7), with: "Next ")
        XCTAssertEqual(content, "Edited 📝 text")
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        XCTAssertEqual(content, "Next 📝 text")
        XCTAssertEqual(coordinator.lastSyncedText, content)
        XCTAssertEqual(edits, ["Edited 📝 text", "Next 📝 text"])
    }

    @MainActor
    func testLongNoteTypingCallbacksPerformance() {
        var content = String(repeating: "A normal note line with some words and emoji 📝.\n", count: 50_000)
        let coordinator = PlainTextEditor.Coordinator(
            text: Binding(get: { content }, set: { content = $0 }),
            cursorPosition: .constant(0), scrollFraction: .constant(0),
            resolveWikiLink: { .missing($0) }, wikiSuggestions: { _ in [] },
            wikiIndexVersion: 0, wikiAutocompleteEnabled: true
        )
        let textView = NSTextView()
        textView.string = content
        coordinator.textView = textView
        let notification = Notification(name: NSText.didChangeNotification, object: textView)
        measure {
            textView.textStorage?.replaceCharacters(in: NSRange(location: textView.textStorage!.length, length: 0), with: "x")
            textView.setSelectedRange(NSRange(location: textView.textStorage!.length, length: 0))
            coordinator.textDidChange(notification)
            coordinator.textViewDidChangeSelection(notification)
        }
        XCTAssertTrue(content.hasSuffix("x"))
    }
}

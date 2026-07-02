import XCTest
@testable import NeoNV

final class SearchSubmissionPolicyTests: XCTestCase {
    func testPartialTitleMatchDoesNotPreventCreation() {
        let note = SearchSubmissionPolicy.NoteIdentity(
            id: UUID(),
            title: "Project Plan",
            relativePath: "project-plan.md"
        )

        let action = SearchSubmissionPolicy.resolve(
            query: "proj",
            notes: [note],
            emptyQueryMatchCount: 1
        )

        XCTAssertEqual(action, .create("proj"))
    }

    func testExactDecoratedTitleOpensExistingNoteCaseInsensitively() {
        let id = UUID()
        let note = SearchSubmissionPolicy.NoteIdentity(
            id: id,
            title: "## Project Plan",
            relativePath: "project-plan.md"
        )

        let action = SearchSubmissionPolicy.resolve(
            query: "project plan",
            notes: [note],
            emptyQueryMatchCount: 1
        )

        XCTAssertEqual(action, .open(id))
    }

    func testFilenameAndBasenameOpenExistingNote() {
        let id = UUID()
        let note = SearchSubmissionPolicy.NoteIdentity(
            id: id,
            title: "A different first line",
            relativePath: "projects/project-plan.md"
        )

        let filenameAction = SearchSubmissionPolicy.resolve(
            query: "PROJECT-PLAN.MD",
            notes: [note],
            emptyQueryMatchCount: 1
        )
        let basenameAction = SearchSubmissionPolicy.resolve(
            query: "project-plan",
            notes: [note],
            emptyQueryMatchCount: 1
        )

        XCTAssertEqual(filenameAction, .open(id))
        XCTAssertEqual(basenameAction, .open(id))
    }

    func testSanitizedCreationDestinationOpensExistingNote() {
        let id = UUID()
        let note = SearchSubmissionPolicy.NoteIdentity(
            id: id,
            title: "A different first line",
            relativePath: "projects/project-plan.md"
        )

        let action = SearchSubmissionPolicy.resolve(
            query: "Projects\\Project Plan",
            notes: [note],
            emptyQueryMatchCount: 1
        )

        XCTAssertEqual(action, .open(id))
    }

    func testWhitespaceOnlyInputDoesNothing() {
        let action = SearchSubmissionPolicy.resolve(
            query: " \n\t ",
            notes: [],
            emptyQueryMatchCount: 0
        )

        XCTAssertEqual(action, .none)
    }

    func testEmptyInputPreservesExistingNavigationBehavior() {
        let noMatches = SearchSubmissionPolicy.resolve(
            query: "",
            notes: [],
            emptyQueryMatchCount: 0
        )
        let oneMatch = SearchSubmissionPolicy.resolve(
            query: "",
            notes: [],
            emptyQueryMatchCount: 1
        )
        let manyMatches = SearchSubmissionPolicy.resolve(
            query: "",
            notes: [],
            emptyQueryMatchCount: 2
        )

        XCTAssertEqual(noMatches, .none)
        XCTAssertEqual(oneMatch, .focusEditor)
        XCTAssertEqual(manyMatches, .navigateToResults)
    }

    func testActionHintDistinguishesCreateFromOpen() {
        XCTAssertEqual(
            SearchSubmissionPolicy.hint(for: .create("proj"), matchCount: 3),
            "3 matches · ⏎ to create"
        )
        XCTAssertEqual(
            SearchSubmissionPolicy.hint(for: .open(UUID()), matchCount: 1),
            "Exact match · ⏎ to open"
        )
    }

    func testMarkupOnlyInputDoesNotMatchAnEmptyTitle() {
        let note = SearchSubmissionPolicy.NoteIdentity(
            id: UUID(),
            title: "",
            relativePath: "untitled.md"
        )

        let action = SearchSubmissionPolicy.resolve(
            query: "#",
            notes: [note],
            emptyQueryMatchCount: 1
        )

        XCTAssertEqual(action, .create("#"))
    }

    func testPartialPathMatchDoesNotPreventCreation() {
        let note = SearchSubmissionPolicy.NoteIdentity(
            id: UUID(),
            title: "Unrelated title",
            relativePath: "archive/project-notes.md"
        )

        let action = SearchSubmissionPolicy.resolve(
            query: "proj",
            notes: [note],
            emptyQueryMatchCount: 1
        )

        XCTAssertEqual(action, .create("proj"))
    }

    func testNormalizedRelativePathOpensExistingNote() {
        let id = UUID()
        let note = SearchSubmissionPolicy.NoteIdentity(
            id: id,
            title: "Unrelated title",
            relativePath: "projects/project-plan.md"
        )

        let action = SearchSubmissionPolicy.resolve(
            query: "PROJECTS\\PROJECT-PLAN",
            notes: [note],
            emptyQueryMatchCount: 1
        )

        XCTAssertEqual(action, .open(id))
    }

    func testFirstExactIdentityWins() {
        let firstID = UUID()
        let notes = [
            SearchSubmissionPolicy.NoteIdentity(
                id: firstID,
                title: "Project Plan",
                relativePath: "newer.md"
            ),
            SearchSubmissionPolicy.NoteIdentity(
                id: UUID(),
                title: "Project Plan",
                relativePath: "older.md"
            )
        ]

        let action = SearchSubmissionPolicy.resolve(
            query: "Project Plan",
            notes: notes,
            emptyQueryMatchCount: 2
        )

        XCTAssertEqual(action, .open(firstID))
    }

    func testConfiguredDefaultExtensionParticipatesInDestinationIdentity() {
        let id = UUID()
        let note = SearchSubmissionPolicy.NoteIdentity(
            id: id,
            title: "Unrelated title",
            relativePath: "project-plan.txt"
        )

        let action = SearchSubmissionPolicy.resolve(
            query: "Project Plan",
            notes: [note],
            emptyQueryMatchCount: 1,
            defaultExtension: "txt"
        )

        XCTAssertEqual(action, .open(id))
    }

    func testTopmostNoteWinsAcrossDifferentExactIdentityKinds() {
        let topID = UUID()
        let notes = [
            SearchSubmissionPolicy.NoteIdentity(
                id: topID,
                title: "Unrelated title",
                relativePath: "project-plan.md"
            ),
            SearchSubmissionPolicy.NoteIdentity(
                id: UUID(),
                title: "Project Plan",
                relativePath: "another-note.md"
            )
        ]

        let action = SearchSubmissionPolicy.resolve(
            query: "Project Plan",
            notes: notes,
            emptyQueryMatchCount: 2
        )

        XCTAssertEqual(action, .open(topID))
    }
}

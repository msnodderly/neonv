# PRD: Deterministic Search-or-Create Submission

## Problem Statement

NeoNV uses one field for both incremental search and note creation, following the modeless interaction style of Notational Velocity. A user can type a prospective note title while related notes appear below, then either navigate into those results or submit the typed title to create a note.

That contract is currently broken. When a non-empty search such as `proj` has one or more partial matches, pressing Return opens the first result instead of creating a note titled `proj`. The selected result takes precedence even when it only matches in part of its title, path, body, or tags. This makes note creation depend on the incidental contents and ordering of the user's collection.

The behavior also conflicts with the intent of pull request 126, which established that search-field Return creates a note unless the input exactly identifies an existing note. A later change deliberately reversed that behavior and added a UI regression test for the reversed contract. The application documentation and search-field hint now describe or imply both behaviors in different places.

As a result, users cannot predict whether Return will create or open, and common short titles become increasingly difficult to create as the note collection grows.

## Solution

Make submission from the search field deterministic and independent of partial search results:

| Search-field input | Return action |
| --- | --- |
| Empty | Preserve the existing empty-query navigation behavior |
| Whitespace only | Do nothing |
| Exactly identifies an existing note | Open the topmost exact match in the editor |
| Does not exactly identify an existing note | Create a note from the input and open it in the editor |

An input exactly identifies a note when it matches any of these case-insensitive identities after the appropriate normalization:

1. The note's first-line title, with surrounding whitespace and supported Markdown title decorators removed.
2. The note's filename, including its recognized extension.
3. The note's basename, without its recognized extension.
4. The note's relative path, with or without its recognized extension.
5. The relative destination path that NeoNV's normal filename and path sanitization would produce from the input.

Path comparisons normalize slash direction and redundant separators. Title comparison remains distinct from path sanitization so meaningful title punctuation is not discarded. If multiple notes share an exact identity, NeoNV opens the first note in the ordering already presented to the user.

Partial matches remain useful context, but they do not alter search-field Return:

- Typing continues to filter the list and preview the top result.
- Tab or Down Arrow moves from search into the result list.
- Return from the result list opens the selected result.
- Return from search creates from a non-exact input, even if a result is auto-selected.

The search-field affordance communicates the pending action:

- A non-exact input shows that Return will create, including when partial matches exist.
- An exact input shows that Return will open the existing note.
- The match count may still be shown, but it must not imply that Return opens a partial match.

Submission uses the current field value synchronously. It must not depend on a stale debounced query or cached result list. Note creation continues through NeoNV's standard creation flow, including path sanitization, default extension selection, directory creation, initial title content, cursor placement, collision protection, and error reporting.

## User Stories

1. As a note taker, I want Return to create the title I typed when no exact note exists, so that creation is predictable.

2. As a note taker, I want `proj` to create a note titled `proj` even when other notes contain `proj`, so that common words remain usable as titles.

3. As a note taker, I want a partial title match to remain visible while I type a new title, so that I can choose whether to use related material instead.

4. As a keyboard-first user, I want Return in the search field to act on my typed text rather than the incidental auto-selection, so that I do not need a mouse to create notes reliably.

5. As a keyboard-first user, I want Tab or Down Arrow to enter the results list, so that opening a partial match remains fast and explicit.

6. As a keyboard-first user, I want Return in the results list to open the selected note, so that search-result navigation retains its existing behavior.

7. As a user searching for an existing note, I want an exact first-line title to open that note, so that I do not create an obvious duplicate.

8. As a user searching for an existing note, I want exact-title matching to ignore letter case, so that capitalization differences do not create duplicates.

9. As a Markdown user, I want a query without heading markers to match a title that begins with Markdown heading markers, so that display formatting does not affect identity.

10. As a user of plain-text files, I want an exact filename to open the existing note, so that disk-backed note identity is respected.

11. As a user of plain-text files, I want a filename query to work with or without a recognized note extension, so that I can use either natural titles or exact filenames.

12. As a user with nested note folders, I want an exact relative path to open the existing note, so that identically named notes can be addressed explicitly.

13. As a user who types Windows-style separators out of habit, I want path comparison to normalize slash direction, so that equivalent relative paths resolve consistently.

14. As a user whose natural title is sanitized into a disk filename, I want NeoNV to recognize the destination filename before creating, so that sanitization does not lead to an overwrite attempt or confusing duplicate behavior.

15. As a user with multiple notes sharing the same exact title or basename, I want Return to open the topmost exact match, so that ambiguous legacy collections still behave deterministically.

16. As a user creating a note, I want the existing default extension and path-sanitization settings to remain in effect, so that this interaction does not introduce a second creation convention.

17. As a user creating a nested note, I want missing intermediate directories to be created through the existing creation flow, so that path-based creation keeps working.

18. As a user creating a note, I want the typed title placed into the new note and the insertion point moved to the expected editing position, so that I can continue writing immediately.

19. As a user, I want NeoNV never to overwrite an existing file during search-based creation, so that an identity race or stale in-memory index cannot lose data.

20. As a user, I want a file that appears during creation to be discovered and opened rather than overwritten, so that external edits remain safe.

21. As a user, I want whitespace-only input to create nothing, so that accidental Return presses do not create untitled files.

22. As a user, I want the established empty-query Return behavior preserved, so that this fix does not alter unrelated pane navigation.

23. As a user typing quickly, I want Return to evaluate all characters currently visible in the field, so that debounce timing cannot open or create the wrong note.

24. As a user, I want Return to be handled without a system beep, so that the application acknowledges the command even when no action is valid.

25. As a user, I want the search field to say when Return will create, so that visible matches do not make the outcome ambiguous.

26. As a user entering an exact identity, I want the search field to say when Return will open, so that duplicate prevention is visible before submission.

27. As a user, I want match counts to remain available, so that I can see how many related notes are available before deciding to create or navigate.

28. As a user with body or tag matches, I want those matches treated as related results rather than exact note identities, so that unrelated content cannot block creation.

29. As a user with an auto-selected preview, I want creating a new note to select and display the newly created note, so that the previously previewed result does not remain active.

30. As a maintainer, I want the submission rule represented once in a testable module, so that UI code, keyboard handling, and documentation cannot silently develop different rules.

31. As a maintainer, I want regression coverage for both creating and opening, so that fixing one side of the interaction does not break the other.

32. As a maintainer, I want tests to cover title, filename, basename, and relative-path identities, so that the exact-match definition remains intentional.

33. As a maintainer, I want an end-to-end test with several partial matches, so that the original `proj` failure is reproduced under realistic conditions.

34. As a maintainer, I want contradictory tests and product documentation removed or updated, so that future changes start from one product contract.

## Implementation Decisions

- Introduce a small, pure search-submission policy module as the authoritative decision point.

- The policy accepts the current raw input, the currently ordered notes represented by lightweight identity data, and the information needed for the preserved empty-query behavior.

- The policy returns an explicit action such as open a particular note, create from the input, navigate to results, focus the existing note, or do nothing. View code executes that action but does not reimplement the decision tree.

- Keep title normalization and path identity normalization within the policy boundary. They are separate operations because display-title markup and filesystem sanitization have different semantics.

- Exact first-line-title comparison trims surrounding whitespace, removes the supported leading Markdown heading, list, or blockquote decorator, trims again, and compares case-insensitively.

- File identity comparison supports recognized extensions, basenames without extensions, and relative paths with normalized separators.

- The policy also compares the input's normal sanitized creation destination with existing note paths. This reuses the same naming rules as creation rather than maintaining an approximate duplicate algorithm.

- If several notes exactly match through any identity, select the first one in the ordering supplied to the policy. The policy does not introduce a second ranking system.

- Title, filename, basename, and path identities are exact-only. Substring, token, fuzzy, body, preview, and tag matches never cause search-field Return to open a note.

- Auto-selection and live preview remain presentation behavior. Selected-note state is not an input to non-empty search submission.

- Search submission cancels or flushes pending debounce work as needed for display consistency, but resolves its action from the current raw field value and current note inventory.

- Preserve the existing empty-query behavior: one available result focuses its editor, multiple results move focus to the list, and no results produce no navigation.

- Treat an input containing only whitespace as invalid non-empty input and produce no create action.

- Continue using the established note-creation operation after the policy returns create. Do not duplicate filename generation, directory creation, file writing, collision handling, note discovery, editor selection, or error presentation inside the policy.

- Preserve the current no-overwrite write behavior and recovery when a destination appears between resolution and creation.

- Derive the search-field action hint from the same resolved policy state used on submission. For a non-exact input with matches, communicate both the match count and that Return creates. For an exact input, communicate that Return opens.

- Preserve Tab, Down Arrow, Up Arrow, Escape, list Return, and focus-cycle behavior.

- Do not add a force-create keyboard modifier. Exact identities open existing notes; users can choose a distinct title or path when they intentionally need another note.

- Update user-facing keyboard help and maintained search/UX documentation to describe the final contract.

- Replace historical statements that claim search-field Return opens a partial top match. Release notes remain historical records and should not be rewritten, but current documentation must supersede them.

- The implementation must not change search matching, result ranking, note ordering, default extension selection, or general note-creation naming rules.

## Testing Decisions

Good tests assert externally observable policy and user behavior rather than private view structure, helper call counts, or SwiftUI implementation details.

Add a unit-test target for the pure submission policy. Table-driven policy tests should cover:

- Non-exact input with no results returns create.
- Non-exact input with one or many partial title matches returns create.
- Non-exact input with body-only, tag-only, or path-substring matches returns create.
- Exact first-line title returns open.
- Exact title matching is case-insensitive.
- Supported Markdown title decorators do not affect exact-title identity.
- Exact filename with extension returns open.
- Exact basename without extension returns open.
- Exact relative path with and without extension returns open.
- Equivalent slash directions in a relative path return open.
- An input whose sanitized destination equals an existing path returns open.
- Multiple exact candidates return the first note in supplied ordering.
- A selected partial note does not influence the action.
- Whitespace-only input returns no action.
- Empty input preserves the zero-, one-, and many-result navigation outcomes.

Extend the UI test suite to cover complete workflows:

- Replace the current test that expects partial-search Return to open the top result.
- Create fixtures containing several notes that match `proj` through different searchable fields.
- Type `proj` and press Return from search; verify a new note file is created, selected, and opened with the expected initial content.
- Type an exact first-line title and press Return; verify the existing note opens and no new file appears.
- Type an exact filename or relative path and press Return; verify the existing note opens.
- Type a partial query, press Tab or Down Arrow, then press Return from the list; verify the selected existing note opens.
- Submit immediately before the search debounce interval completes; verify the full current input determines the action.
- Verify whitespace-only Return creates no file and produces no system beep or unexpected focus transition where test infrastructure can observe it.
- Verify the search-field hint communicates create while partial matches exist and open for an exact identity.

Use the existing generated-fixture UI suite, on-disk file polling helpers, editor accessibility identifiers, and search-navigation tests as prior art. Keep fixtures isolated through the existing test notes directory so no test touches the user's real notes.

Build the application and run both the new unit-test target and the existing UI test target. Manual smoke testing remains necessary because first-responder behavior, key handling, visible hints, and the absence of a macOS system beep are not fully represented by automated assertions.

## Out of Scope

- Changing the incremental search algorithm, tokenization, full-content indexing, ranking, or debounce duration.

- Adding fuzzy identity matching. Exact identity resolution remains intentionally narrower than search matching.

- Adding a force-create shortcut such as Command-Return or Shift-Return.

- Adding a chooser for duplicate exact titles. The topmost exact result is deterministic and sufficient for this scope.

- Changing the note list's automatic top-result selection or live editor preview.

- Changing filename sanitization, allowed extensions, default extension selection, or subdirectory creation rules.

- Renaming or migrating existing note files.

- Changing the behavior of Command-N.

- Rewriting historical release notes.

- Reproducing every Notational Velocity behavior beyond the unified search/create interaction.

## Further Notes

- Pull request 126 documented the intended “create unless exact title match” behavior and remains the direct product precedent: <https://github.com/msnodderly/neonv/pull/126>.

- Notational Velocity established the core model of using the same field for searching and creating, with related notes appearing while a prospective title is typed: <https://notational.net/>.

- NeoNV's rule is deliberately more explicit than Notational Velocity's public wording about creating when a search reveals no results. In NeoNV, partial results are advisory; exact identity alone changes Return from create to open.

- The regression was introduced by commit `ea2bba1`, which inserted an “open first current match” branch before creation and added a UI test asserting that reversed behavior.

- The implementation should be reviewed as a product-contract correction, not merely a branch deletion. Centralizing the policy, aligning the action hint, and replacing the contradictory regression test are required to prevent recurrence.

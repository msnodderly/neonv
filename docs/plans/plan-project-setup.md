# Plan: SETUP-002 - Create Xcode Project

## Objective
Initialize the project structure for "neonv", a native macOS application using SwiftUI.

## Current Environment Status
- **OS**: macOS 15.0 (Sequoia) - Compatible with macOS 14.0 target.
- **Tooling**:
    - `swift`: Available (6.0.3).
    - `xcodegen`: Not found.
    - `xcodebuild`: Error (Active directory is Command Line Tools, not Xcode).
- **Constraint**: Cannot verify builds using `xcodebuild` until `xcode-select` is pointed to Xcode.app. Cannot generate `.xcodeproj` binary/bundle easily without `xcodegen`.

## Strategy: Swift Package Manager App
Due to the lack of `xcodegen` and the text-only interface, we will create a **Swift Package** executable. This is a modern, valid way to define a macOS app that Xcode can open and build directly.

### Benefits
- **Text-based configuration**: `Package.swift` is easy to read/write/modify.
- **No opaque project files**: Avoids the complexity of `project.pbxproj`.
- **Forward compatible**: Xcode treats `Package.swift` as a project.

## Steps

### 1. Project Initialization
- [ ] Create the project root directory (if not already effectively the root).
- [ ] Initialize a Swift executable package:
  ```bash
  swift package init --type executable --name neonv
  ```

### 2. Configuration (`Package.swift`)
- [ ] Set platform requirement to **macOS 14.0 (Sonoma)**.
- [ ] Define the executable target "neonv".

### 3. Source Implementation
- [ ] **Delete** `main.swift`.
- [ ] **Create** `Sources/neonv/neonvApp.swift`:
    - Define the `@main` struct conforming to `App`.
    - Implement `WindowGroup`.
- [ ] **Create** `Sources/neonv/ContentView.swift`:
    - Implement the basic Three-Pane Layout (MVP-001 preparation).
    - Left: List placeholder.
    - Right: Editor placeholder.
    - Top: Search bar placeholder.

### 4. Info.plist Handling
- Swift Packages don't have a built-in `Info.plist` in the same way, but for a simple executable, we can rely on defaults or add a custom `Info.plist` if we convert to an Xcode project later or use specific SwiftPM settings (Swift 5.9+ supports some resource bundling).
- *Note*: For a full GUI app experience (icon, permissions), we might eventually need a real `.xcodeproj` wrapper, but this starts the development.

### 5. Verification
- [ ] Run `swift build` to ensure the code compiles (CLI tools should support compilation).
- [ ] Note for user: "To run the app, open the folder in Xcode or use `swift run` (though `swift run` might not handle the GUI main loop correctly without a proper app bundle context, usually it works for dev)."

## Workaround for `xcode-select`
- I will include a check/suggestion for the user to run:
  `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
  This is required for `xcodebuild` and proper AppKit linking usually.

## Execution Plan
1. Validate directory permissions (currently in `docs`, need to move to root or `src`).
2. Run `swift package init`.
3. Overwrite `Package.swift` with correct config.
4. Write `neonvApp.swift` and `ContentView.swift`.
5. Attempt build.

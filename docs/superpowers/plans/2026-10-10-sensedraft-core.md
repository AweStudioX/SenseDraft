# SenseDraft Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a usable native macOS menu bar app that analyzes the entire focused English input without a selection, lets the user correct the Chinese interpretation, and replaces the captured field only after an explicit shortcut.

**Architecture:** A Swift Package separates pure session and language logic from AppKit/Accessibility adapters. The menu bar executable owns the panel and global hotkeys. OpenAI Responses is the first inference provider; the provider interface permits ChatGPT plan OAuth in a separate plan.

**Tech Stack:** Swift 6.3, Swift Package Manager, AppKit, SwiftUI, ApplicationServices, Carbon hotkeys, Security Keychain, URLSession, XCTest.

## Global Constraints

- The Analyze and Replace actions require separate configurable global shortcuts; typing alone never initiates analysis.
- Analyze reads the entire focused editable field without selecting text.
- Replace verifies the original app, field, and exact captured value before writing. Panel focus is allowed; another external field invalidates the session.
- Protected fields and unsupported rich text editors are never silently read or overwritten.
- Input and output are not retained by default; logs omit content and credentials.
- The initial language target is US English. The user can edit the Chinese interpretation to regenerate English.
- This plan covers API Key inference. ChatGPT plan OAuth is in a separate plan and must not delay a working core app.

## File map

| File | Responsibility |
| --- | --- |
| `Package.swift` | macOS executable, core library, and test targets |
| `Sources/SenseDraftCore/Analysis.swift` | Request and result types, validation |
| `Sources/SenseDraftCore/Session.swift` | Captured target identity, stale checks, request generations |
| `Sources/SenseDraftCore/LanguageService.swift` | Provider protocol, prompts, response decoding |
| `Sources/SenseDraftCore/OpenAIProvider.swift` | Responses API requests and errors |
| `Sources/SenseDraftMac/AccessibilityField.swift` | Focused element capture and guarded replacement |
| `Sources/SenseDraftMac/GlobalHotkeys.swift` | Carbon shortcut registration and conflict errors |
| `Sources/SenseDraftMac/Keychain.swift` | Per-user API key storage |
| `Sources/SenseDraftMac/Panel.swift` | AppKit panel hosting SwiftUI content |
| `Sources/SenseDraftMac/Settings.swift` | General, AI, Shortcuts, and Permissions settings window |
| `Sources/SenseDraftMac/PermissionGuide.swift` | Accessibility status, prompt, and System Settings handoff |
| `Sources/SenseDraftMac/SenseDraftApp.swift` | Menu bar lifecycle and wiring |
| `Tests/SenseDraftCoreTests/*` | Pure behavior and provider decoding tests |
| `Scripts/build-app.sh` and `Resources/Info.plist` | Bundle executable as `SenseDraft.app` for Accessibility consent |

---

### Task 1: Package and analysis contract

**Files:** Create `Package.swift`, `Sources/SenseDraftCore/Analysis.swift`, `Tests/SenseDraftCoreTests/AnalysisTests.swift`.

**Interfaces:** `AnalysisInput(source: String, locale: String, chineseIntent: String?)`; `AnalysisResult(english: String, chineseMeaning: String, ambiguity: String?)`; `AnalysisError` for empty or invalid output.

- [ ] Write an XCTest that constructs `AnalysisInput` with a nonempty field and rejects empty or whitespace-only source; assert an `AnalysisResult` rejects blank English or Chinese meaning.
- [ ] Run `swift test --filter AnalysisTests`; expect a compile failure because the types do not exist.
- [ ] Add a Swift package with macOS 14 minimum, a `SenseDraftCore` library, `SenseDraftMac` executable, and `SenseDraftCoreTests`. Add the two value types and their throwing validators. Avoid dependencies.
- [ ] Run `swift test --filter AnalysisTests`; expect all cases to pass. Commit as `feat: add analysis contract`.

### Task 2: Captured-field session and stale protection

**Files:** Create `Sources/SenseDraftCore/Session.swift`, `Tests/SenseDraftCoreTests/SessionTests.swift`.

**Interfaces:** `TargetSnapshot(appID: String, elementID: String, source: String)`; `AnalysisSession(snapshot: TargetSnapshot, generation: UUID, result: AnalysisResult?)`; `canReplace(currentAppID: String, currentElementID: String, currentValue: String) -> Bool`.

- [ ] Write tests that allow replacement for the exact target and source; reject changed text, another app, and another external field. Test that a newer generation makes an old response ineligible.
- [ ] Run `swift test --filter SessionTests`; expect a compile failure because `TargetSnapshot` and `AnalysisSession` are missing.
- [ ] Implement immutable snapshot comparison and generation matching. Keep panel focus out of the session predicate; the macOS adapter identifies whether focus is the app's own panel.
- [ ] Run `swift test --filter SessionTests` and `swift test`; expect pass. Commit as `feat: guard replacement session`.

### Task 3: Language provider and response validation

**Files:** Create `Sources/SenseDraftCore/LanguageService.swift`, `Sources/SenseDraftCore/OpenAIProvider.swift`, `Tests/SenseDraftCoreTests/LanguageServiceTests.swift`, `Tests/SenseDraftCoreTests/OpenAIProviderTests.swift`.

**Interfaces:** `LanguageService.analyze(_ input: AnalysisInput) async throws -> AnalysisResult`; `OpenAIProvider(key: String, transport: HTTPTransport)`; `HTTPTransport.send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)`.

- [ ] Write tests for initial analysis instructions: retain names, numbers, commitments, uncertainty, and meaning. Write a second test that an edited Chinese intention is marked authoritative. Write decoding tests for valid output, incomplete output, non-2xx status, and missing `response.completed` when streaming is used.
- [ ] Run the focused tests; expect compile failures for the missing provider and transport.
- [ ] Implement the provider using the public Responses API and `URLSession` transport. Request a structured result containing `english`, `chineseMeaning`, and optional `ambiguity`; validate every field before exposing it. Keep the API key only in the Authorization header, never in errors or logs. Store responses only in memory.
- [ ] Run `swift test`; expect pass. Commit as `feat: analyze meaning with OpenAI`.

### Task 4: Accessibility adapter with guarded write

**Files:** Create `Sources/SenseDraftMac/AccessibilityField.swift`, `Tests/SenseDraftCoreTests/FieldPolicyTests.swift` and a pure `Sources/SenseDraftCore/FieldPolicy.swift`.

**Interfaces:** `FieldPolicy.validate(role: String, protected: Bool, editable: Bool, value: String) throws`; `AccessibilityField.captureFocused() throws -> CapturedField`; `CapturedField.replaceIfUnchanged(with: String) throws`.

- [ ] Write tests that reject protected, blank, noneditable, and unsupported roles and accept a normal editable text area. Run the focused test and verify red.
- [ ] Implement `FieldPolicy`. Implement the macOS adapter with `AXIsProcessTrustedWithOptions`, `AXUIElementCopyAttributeValue`, and capability checks. Save an `AXUIElement` reference and originating process ID. Before writing, re-read the same element and compare exact source text; do not trust only the newly focused element. Confirm the written value by reading it back. Return a specific unsupported error when AX reading/writing is absent.
- [ ] Run `swift test` and `swift build`; expect pass. Manually exercise capture/write in TextEdit before claiming integration success. Commit as `feat: capture and replace focused field`.

### Task 5: Global shortcuts, panel, and app lifecycle

**Files:** Create `Sources/SenseDraftMac/GlobalHotkeys.swift`, `Sources/SenseDraftMac/Panel.swift`, `Sources/SenseDraftMac/SenseDraftApp.swift`, `Sources/SenseDraftMac/Keychain.swift`, `Sources/SenseDraftMac/Settings.swift`, `Sources/SenseDraftMac/PermissionGuide.swift`, `Tests/SenseDraftCoreTests/HotkeySettingsTests.swift`, and `Sources/SenseDraftCore/HotkeySettings.swift`.

**Interfaces:** `HotkeySettings` rejects identical Analyze/Replace shortcuts; `GlobalHotkeys` registers them and reports OS conflicts; panel callbacks `onRegenerate(chinese: String)` and `onCopy()`.

- [ ] Write a test for default shortcut separation and conflict rejection; run it and verify red.
- [ ] Implement `HotkeySettings`. Register shortcuts with Carbon `RegisterEventHotKey` and unregister on shutdown. Add a menu bar item to open settings and quit. Build an AppKit panel with SwiftUI text controls and visible source, English, Chinese interpretation, ambiguity, loading/error, regeneration, and copy states. Keep the captured external field reference when panel gains focus.
- [ ] Add a settings window with General, AI, Shortcuts, and Permissions tabs. Persist provider, model, locale, and shortcut choices in user defaults; store the API Key only in Keychain. Detect duplicate or unregistrable shortcuts and retain the previous active shortcuts on failure. Show permission status, request access, and open macOS Accessibility settings. Present the guide on first launch.
- [ ] Wire Analyze to `captureFocused` then `LanguageService.analyze`; wire Replace to `replaceIfUnchanged`; wire regeneration to a new request using edited Chinese. Store the user's API key in Keychain and make provider identity visible. Run `swift test` and `swift build`; expect pass. Manually verify both shortcuts in TextEdit. Commit as `feat: add SenseDraft menu bar workflow`.

### Task 6: App bundle and compatibility gate

**Files:** Create `Resources/Info.plist`, `Scripts/build-app.sh`, `README.md`, `docs/compatibility.md`.

**Interfaces:** `Scripts/build-app.sh` produces `build/SenseDraft.app` with a stable bundle identifier and executable, suitable for macOS Accessibility permission registration.

- [ ] Add a shell verification step that builds the app and checks `Contents/MacOS/SenseDraftMac` and the bundle identifier in `Info.plist`; run it and verify failure before creating the script.
- [ ] Create the bundle script and minimal plist; document build/run, Accessibility permission, API key setup, shortcuts, and privacy behavior.
- [ ] Run `swift test`, `swift build`, and the bundle verification. Manually test native AppKit, Safari and Chrome textarea/contenteditable, and representative messaging editors. Record each editor's read and replace result in `docs/compatibility.md`, with copy fallback for unsupported cases. Commit as `build: package and verify SenseDraft`.

## Review gate

The core is complete only when the app bundle runs, tests pass, both shortcuts work without selecting text in at least one native and one browser input, stale source does not get overwritten, and the compatibility document records actual tested editors. Do not claim universal support from one successful editor.

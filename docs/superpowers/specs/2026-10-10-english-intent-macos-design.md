# English Intent for macOS — product design

Date: 2026-10-10
Status: approved in conversation on 2026-10-10; written spec pending user review

## Purpose

Help a Chinese-speaking user send natural English without losing their intended meaning. The user works in the current macOS text input, invokes analysis with a shortcut, checks the proposed English against a Chinese interpretation, optionally edits the Chinese interpretation, and invokes replacement with a second shortcut. Neither action requires selecting text.

“Local English” means idiomatic English suited to the chosen locale. It does not mean offline inference. The initial locale is US English; this can become a preference later.

## User experience

1. The user types English in an editable field in another app.
2. The user presses the configurable **Analyze** shortcut. The app reads the complete value of the focused editable field and records its source application, accessibility element, value, and current revision context. It does not start inference merely because the user types.
3. A compact panel near the field shows the source, improved English, Chinese interpretation, and a specific ambiguity note only when needed. The English is editable in the panel.
4. If the Chinese interpretation misstates the intention, the user edits it and chooses **Regenerate from Chinese**. The resulting English is shown for review; regeneration never writes to the original field.
5. The user presses the configurable **Replace** shortcut. The app checks that the captured target is still the intended field and its value still matches the captured source. Focus on this app's panel is allowed; focus on a different external field invalidates the session. If the checks pass, it replaces the complete field value with the approved English. Otherwise it leaves the field untouched and offers reanalysis or copy.
6. Escape closes the panel without changing the field. Copy English remains available whenever direct replacement is unsupported.

The panel may take keyboard focus for editing. Target identity is saved separately, so the Replace shortcut never mistakes the panel's Chinese editor for the source field.

## Scope

- Entire focused input field, including multiline text. No selection is required.
- English input only for the initial product. Mixed-language input is reported as unsupported instead of silently rewriting the wrong parts.
- Plain text fidelity for cross-application replacement. For rich text, the app must warn if writing would discard formatting and offer copy instead.
- Password, payment, and other protected fields are excluded.
- No continuous keyboard capture, passive reading of other fields, OCR, screenshot translation, history sync, or automatic replacement.

## Architecture

### Input adapter

A native Swift macOS menu bar app uses Accessibility APIs to find the frontmost application's focused element. It checks that the element is editable and unprotected, reads its text value, and captures a stable target reference while the panel is open. A compatibility adapter may use a user initiated copy path for an unsupported editor only if it can reliably preserve and restore clipboard content and selection; otherwise it returns a clear unsupported result. No fallback may silently replace text.

### Session controller

Each analysis has an immutable source snapshot and an incrementing request ID. The controller owns states: `idle`, `capturing`, `analyzing`, `ready`, `regenerating`, `replacing`, `stale`, and `failed`. A newer analysis cancels or supersedes an older one. The session becomes stale when the source value or target cannot be verified at replacement time.

### Language service

A provider interface accepts source English, target locale, and optionally an edited Chinese intention. It returns improved English, Chinese interpretation, an ambiguity indicator, and a concise reason. The first request preserves meaning, names, numbers, commitments, and degree of certainty. The reverse request treats the user's edited Chinese as authoritative while retaining useful details from the source. The app validates the returned structure and reports incomplete or failed responses without modifying the source.

The app supports two credential paths behind this interface: a user supplied OpenAI API key, stored in macOS Keychain, and Sign in with ChatGPT plan usage for eligible users. The latter uses the officially documented OAuth permission and eligible Responses API route, with model discovery and completion handling. Usage limits, revoked permission, and ineligible accounts surface actionable errors. The app never reads Codex's local authentication files or calls private ChatGPT endpoints. A paid or remotely hosted distribution would need a separate eligibility review for plan usage.

### Panel and hotkeys

An AppKit panel, with SwiftUI content where practical, displays the candidate and lets the user edit the Chinese interpretation and English candidate. A hotkey manager owns Analyze and Replace across apps, allows reassignment, and detects conflicts. Panel placement uses the focused field's bounds when available, falling back to a predictable position in the frontmost window. Loading, ambiguity, stale-target, and unsupported-field states have distinct messages.

### Replacement adapter

Replacement first verifies source application, target element, editability, and exact source value. It attempts the least disruptive supported text operation for that editor, then reads back the field to confirm the intended value. If write or verification fails, it reports the outcome and keeps the candidate available for copy. It must not automatically retry via a different operation after an uncertain write, because that could duplicate text.

## Privacy and permissions

Accessibility permission is requested with a plain explanation of why current-field access is needed. The app reads a field only after the Analyze shortcut. It sends only the captured text and necessary instructions to the selected inference provider. Input and output are not retained by default; diagnostic logs omit text and credentials. Credentials are stored in Keychain. The interface identifies which provider is active before a request.

## Failure handling

- No focused editable field, empty field, protected field, or non-English text: explain the condition without starting a model request.
- Accessibility attribute missing or target application does not support a reliable read: explain and offer a user initiated copy path where safe.
- Network, provider, OAuth, rate or subscription limit, refusal, or malformed output: keep the source unchanged; permit retry or provider switch.
- Source changed, target closed, or focus moved to a different external field before Replace: treat the session as stale and do not write. Focus on the app's own panel is expected and does not stale the session.
- Verification after replacement fails: report uncertainty, preserve the candidate, and never repeat the write automatically.

## Acceptance criteria

1. Analyze reads the whole focused field without selecting text or modifying source, and no inference occurs from typing alone.
2. The panel displays improved English and Chinese interpretation. Editing Chinese and regenerating changes the candidate without touching source.
3. Replace works by shortcut only after explicit review and acts on the captured source field, not the panel's editor or a newly focused field.
4. If the source changes between analysis and replacement, the app refuses to overwrite it.
5. Protected fields are ignored. Failed read, write, network, and auth flows never silently modify source.
6. User tests cover native AppKit fields, Safari and Chrome `textarea`/contenteditable, and representative messaging editors. Results are documented per app and editor type; unsupported cases expose copy rather than claiming universal replacement.
7. API key and eligible ChatGPT plan sign-in each complete a real analysis request, with visible handling of denied access and exhausted usage.

## References

- Bob input box translation: https://bobtranslate.com/guide/quickstart/translate.html
- Apple Accessibility attributes and notifications: https://developer.apple.com/documentation/applicationservices
- Apple accessibility write operation: https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue
- OpenAI Sign in with ChatGPT: https://developers.openai.com/siwc/quickstart
- OpenAI plan usage requirements: https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference

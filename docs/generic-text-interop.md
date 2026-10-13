# Generic macOS text capture and replacement

Date: 2026-10-10

## Finding

SenseDraft's current direct `AXValue` read is too narrow. Sublime Text can accept normal Select All, Copy, and Paste commands even when its editor text is absent from the Accessibility tree. Bob confirms that a no-selection, whole-input workflow is practical without an editor plugin. Bob is proprietary, so its exact implementation is unknown; its documentation explicitly warns users not to change the selection or switch apps during replacement. Open-source macOS writing tools independently use Accessibility first, then a temporary clipboard copy/paste path.

This is a capability ladder, not a list of app-specific adapters. The fallback works only when the active editor responds to standard text commands and the transaction can be verified. No public macOS API guarantees full-text access and safe replacement in every third-party editor.

## Capture ladder

1. **Direct Accessibility text.** Snapshot the frontmost process, focused window, focused element, and selected range. Read `AXValue` when available. If the value is absent, try `AXNumberOfCharacters` with `AXStringForRange`. Reject protected fields.
2. **Shortcut-triggered keyboard copy.** Only after direct reads fail, snapshot all clipboard item representations and the active process/window. Send Select All and Copy to the still-focused source. Require a clipboard ownership change and a bounded, nonempty plain-text result. Check that process/window/focus did not change. Restore the clipboard only if its change count still matches the temporary copy.
3. **Restore selection.** Prefer the saved Accessibility selection range. Where it is unavailable, the current implementation discloses that the caret will move to the end when the temporary selection is collapsed. A discoverable Undo Selection command is a possible later refinement. It must never leave all text selected without telling the user.
4. **No reliable read.** Do not send text to AI. Show a concise reason and offer manual paste into SenseDraft.

The keyboard path begins only on Analyze. It does not watch keystrokes, use OCR, read the clipboard in the background, or require users to preselect text. When Accessibility identifies a non-text control, capture is rejected. When it exposes only the window, a successful Copy cannot prove that the source is an editable input rather than selected page or document text. The panel therefore displays the copied source for review, and replacement still requires a separate shortcut, a matching window and source, and post-write verification. A temporary copy may still be seen by clipboard-history apps; this cannot be prevented through `NSPasteboard`.

## Replacement transaction

1. The user reviews the English and Chinese, then focuses the original editor and presses Replace. The review panel remains available.
2. Check the saved process and window identity, plus focused element identity where available. Re-read the entire source through the same capability path and compare exact text with the original snapshot. A mismatch cancels without writing.
3. Use direct `AXValue` for single-line text fields. For multiline text areas and keyboard-only targets, return focus to the editor, Select All, verify the copied source, place the candidate temporarily on the clipboard, and Paste once. The user has explicitly invoked Replace, and the panel must warn that rich formatting may be lost. Some editors accept an `AXValue` write but append rather than replace, so `AXValue` settable is insufficient evidence for multiline replacement.
4. Re-read the target to confirm the candidate. Restore the clipboard only if the temporary value is still owned by SenseDraft. If the write cannot be verified, show an uncertain result and do not retry automatically.

For Chromium contenteditable fields, the Accessibility value can contain trailing zero-width placeholder lines that Select All / Copy omits. Compare these two representations after stripping only that specific trailing placeholder pattern from the Accessibility value. Preserve ordinary trailing newlines and internal zero-width characters; all other mismatches still cancel replacement.

Window identity and exact text checks substantially reduce wrong-target writes. When an editor exposes no stable element identity, replacement is allowed only while that same application/window is again frontmost and the source text matches exactly. A window containing two identical editors remains an edge case; the UI must make the active target clear. The product cannot promise identical behavior across arbitrary terminal, remote-desktop, game, or protected inputs.

## Implementation and validation order

The code now implements the two read paths, clipboard snapshot/ownership checks, a 100 KB text limit, a generic keyboard capture adapter, and replacement with exact-source and post-write verification. Automated core tests and build checks can establish compilation and model behavior, but **live Accessibility/keyboard integration remains to be tested on the packaged app**. The manual matrix is TextEdit, Sublime Text, Slack, Safari, and Chrome with no preselection, including empty, protected, rich-text, switched-focus, and changed-clipboard cases. Do not treat a successful copy as evidence that paste is safe.

## Evidence

- [Bob whole-input translation](https://bobtranslate.com/blog/2025-08-11-silent-translate.html) and [Bob feature guide](https://bobtranslate.com/guide/quickstart/translate.html): no-selection capture/replacement, with a warning about changing selection or apps.
- [Bob repository](https://github.com/ripperhe/Bob): current app is not open source.
- [Apple Accessibility text range](https://developer.apple.com/documentation/applicationservices/kaxstringforrangeparameterizedattribute) and [parameterized attribute API](https://developer.apple.com/documentation/applicationservices/1461203-axuielementcopyparameterizedattr): another direct read path when `AXValue` is unavailable.
- [Apple pasteboard change count](https://developer.apple.com/documentation/appkit/nspasteboard/changecount): ownership check before restoration.
- [Electron macOS Accessibility guidance](https://www.electronjs.org/docs/latest/tutorial/accessibility) and [Electron text-range issue #36337](https://github.com/electron/electron/issues/36337): Chromium-based desktop editors can expose text and selection through AX differently from native editors.
- [Inklet](https://github.com/wanming/inklet) and [TypeTide](https://github.com/everettjf/TypeTide): independent application-agnostic Accessibility plus clipboard fallback designs.
- [Sublime selection documentation](https://www.sublimetext.com/docs/multiple_selection_with_the_keyboard.html): Undo Selection is available on macOS, though it is not a universal macOS command.

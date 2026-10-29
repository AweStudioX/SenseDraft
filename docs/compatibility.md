# Editor compatibility

The table records direct observations from the packaged `SenseDraft.app`. A successful compile is not evidence that a third-party editor supports Accessibility writes.

| App / editor | Read full field | Replace full field | Notes |
| --- | --- | --- | --- |
| TextEdit plain text | Pending manual test | Pending manual test | Native AppKit |
| Safari textarea | Pending manual test | Pending manual test | Browser editor |
| Chrome textarea | Pending manual test | Pending manual test | Browser editor |
| Safari/Chrome contenteditable | Pending manual test | Pending manual test | Rich text may need copy fallback |
| Slack message composer | User observed `windowUnavailable`; updated resolver needs retest | Pending packaged-app test | Slack exposes a settable text entry area, but the user's capture failed because SenseDraft could not resolve its window through the focused or main window attributes. The updated keyboard fallback also checks the focused element's window ancestor and a single window in the application's window list. Capture and replacement need a live retest. |
| Feishu message composer | User confirmed intermittently; `windowUnavailable` observed on October 23 | User confirmed intermittently; latest change needs retest | The installed Feishu bundle is `com.electron.lark`, with a Chromium `Lark Framework` and separate messenger WebViews. Its AX text entry area exposes trailing zero-width placeholder lines absent from copied visible text. The same running SenseDraft process logged two Feishu replacements with matching passive readback on October 23, then the user showed a capture failure because AX did not identify the editor window. Capture now retries window resolution briefly while the source app remains frontmost and logs only whether a focused element exists and how many AX windows are exposed. This needs a fresh packaged-app retest. |
| Sublime Text editor | Keyboard fallback built; live test pending | Keyboard fallback built; live test pending | In the observed Sublime window, Accessibility exposed the window and title but no readable focused editor value. The generic shortcut-triggered Select All/Copy/Paste fallback now handles this capability gap without a plugin; capture, clipboard restoration, and replacement still need a packaged-app test. |

## Bob comparison

Bob documents a shortcut that translates the entire focused input box without a prior text selection, then replaces its contents. It asks users to leave the caret in that input and avoid switching apps during translation. Its [current repository](https://github.com/ripperhe/Bob) says the app is not open source, so its exact Sublime capture and replacement mechanism cannot be established from published code. See [Bob's input-box guide](https://bobtranslate.com/guide/quickstart/translate.html) and [feature announcement](https://bobtranslate.com/blog/2025-08-11-silent-translate.html).

SenseDraft now has a no-plugin, application-agnostic keyboard fallback. It snapshots the active app/window and clipboard, selects and copies the full input only after Analyze, restores the clipboard if its ownership has not changed, and collapses the selection when it cannot restore a saved Accessibility range. In that case the caret moves to the end, which the review panel discloses. Replace requires the user to refocus the same window, compares the entire source again, pastes once, and verifies the result. A clipboard manager may still record the transient copy. This is our implementation, **not a verified description of Bob's internals**. Sublime documents **⌘U** as Undo Selection, which is an option for later refinement; see its [keyboard selection documentation](https://www.sublimetext.com/docs/multiple_selection_with_the_keyboard.html).

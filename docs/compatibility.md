# Editor compatibility

The table records direct observations from the packaged `SenseDraft.app`. A successful compile is not evidence that a third-party editor supports Accessibility writes.

| App / editor | Read full field | Replace full field | Notes |
| --- | --- | --- | --- |
| TextEdit plain text | Pending manual test | Pending manual test | Native AppKit |
| Safari textarea | Pending manual test | Pending manual test | Browser editor |
| Chrome textarea | Pending manual test | Pending manual test | Browser editor |
| Safari/Chrome contenteditable | Pending manual test | Pending manual test | Rich text may need copy fallback |
| Slack message composer | Pending packaged-app test | Pending packaged-app test | Slack exposes the focused composer as a settable text entry area. SenseDraft now queries Slack's application focus directly when the global focus query is unavailable; live capture and replacement still need confirmation. |
| Sublime Text editor | Keyboard fallback built; live test pending | Keyboard fallback built; live test pending | In the observed Sublime window, Accessibility exposed the window and title but no readable focused editor value. The generic shortcut-triggered Select All/Copy/Paste fallback now handles this capability gap without a plugin; capture, clipboard restoration, and replacement still need a packaged-app test. |

## Bob comparison

Bob documents a shortcut that translates the entire focused input box without a prior text selection, then replaces its contents. It asks users to leave the caret in that input and avoid switching apps during translation. Its [current repository](https://github.com/ripperhe/Bob) says the app is not open source, so its exact Sublime capture and replacement mechanism cannot be established from published code. See [Bob's input-box guide](https://bobtranslate.com/guide/quickstart/translate.html) and [feature announcement](https://bobtranslate.com/blog/2025-08-11-silent-translate.html).

SenseDraft now has a no-plugin, application-agnostic keyboard fallback. It snapshots the active app/window and clipboard, selects and copies the full input only after Analyze, restores the clipboard if its ownership has not changed, and collapses the selection when it cannot restore a saved Accessibility range. In that case the caret moves to the end, which the review panel discloses. Replace requires the user to refocus the same window, compares the entire source again, pastes once, and verifies the result. A clipboard manager may still record the transient copy. This is our implementation, **not a verified description of Bob's internals**. Sublime documents **⌘U** as Undo Selection, which is an option for later refinement; see its [keyboard selection documentation](https://www.sublimetext.com/docs/multiple_selection_with_the_keyboard.html).

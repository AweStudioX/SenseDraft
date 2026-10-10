# Editor compatibility

The table records direct observations from the packaged `SenseDraft.app`. A successful compile is not evidence that a third-party editor supports Accessibility writes.

| App / editor | Read full field | Replace full field | Notes |
| --- | --- | --- | --- |
| TextEdit plain text | Pending manual test | Pending manual test | Native AppKit |
| Safari textarea | Pending manual test | Pending manual test | Browser editor |
| Chrome textarea | Pending manual test | Pending manual test | Browser editor |
| Safari/Chrome contenteditable | Pending manual test | Pending manual test | Rich text may need copy fallback |
| Slack message composer | Pending packaged-app test | Pending packaged-app test | Slack exposes the focused composer as a settable text entry area. SenseDraft now queries Slack's application focus directly when the global focus query is unavailable; live capture and replacement still need confirmation. |
| Sublime Text editor | No with current AX capture | No with current AX replacement | In the observed Sublime window, Accessibility exposed the window and title but no readable focused editor value. Bob's no-selection input-box translation demonstrates a no-plugin path, so the earlier assertion that a Sublime plugin is required was too strong. SenseDraft needs a separately verified fallback. |

## Bob comparison

Bob documents a shortcut that translates the entire focused input box without a prior text selection, then replaces its contents. It asks users to leave the caret in that input and avoid switching apps during translation. Its [current repository](https://github.com/ripperhe/Bob) says the app is not open source, so its exact Sublime capture and replacement mechanism cannot be established from published code. See [Bob's input-box guide](https://bobtranslate.com/guide/quickstart/translate.html) and [feature announcement](https://bobtranslate.com/blog/2025-08-11-silent-translate.html).

A plausible no-plugin fallback for editors without readable Accessibility text is to select and copy the field through simulated keyboard input, then restore the pasteboard. That is an inference, not a verified description of Bob. Sublime documents **⌘U** as Undo Selection, which may restore the caret after **⌘A** and **⌘C**; see its [keyboard selection documentation](https://www.sublimetext.com/docs/multiple_selection_with_the_keyboard.html). SenseDraft should only use such a fallback after checking that it can identify the same target, preserve the original selection and clipboard, and re-read the exact source before replacement. This has not yet been demonstrated for Sublime.

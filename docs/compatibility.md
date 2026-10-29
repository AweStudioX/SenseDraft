# Editor compatibility

On October 29, 2026, the user reported that **Analyze triggers and recognizes text in every non-terminal editor tested so far**. Terminal utility apps were the exception: text recognition did not work there. The report did not identify every app/version or confirm that the entire field was captured in each case. Recognition also does not establish that Replace works.

The table keeps app-specific full-field and replacement evidence separate from that overall report. A successful compile is not evidence that a third-party editor supports Accessibility writes.

| App / editor | Read full field | Replace full field | Notes |
| --- | --- | --- | --- |
| TextEdit plain text | Covered by the user's overall non-terminal recognition report; full-field check pending | Pending manual test | Native AppKit; app-specific result not recorded |
| Safari textarea | Covered by the overall report; full-field check pending | Pending manual test | Browser editor; app-specific result not recorded |
| Chrome textarea | Covered by the overall report; full-field check pending | Pending manual test | Browser editor; app-specific result not recorded |
| Safari/Chrome contenteditable | Covered by the overall report; full-field check pending | Pending manual test | Rich text may need copy fallback; app-specific result not recorded |
| Slack message composer | Covered by the current overall report; full-field check pending | Pending packaged-app test | An earlier attempt returned `windowUnavailable`. The updated resolver checks the focused element's window ancestor and a single window in the application's window list. App-specific capture and replacement details still need recording. |
| Feishu message composer | Covered by the current overall report; full-field check pending | User confirmed intermittently; latest change needs retest | Earlier attempts were intermittent, including `windowUnavailable` on October 23. Capture now retries window resolution briefly while the source app remains frontmost. The current report establishes text recognition across tested non-terminal editors, but not a Feishu-specific replacement result. |
| Sublime Text editor | Covered by the current overall report; full-field check pending | Keyboard fallback built; live test pending | Earlier Accessibility inspection exposed the window but no readable editor value. The keyboard fallback may capture text; app-specific full-field and replacement checks remain pending. |
| Terminal utility apps | User reports text recognition does not work | Not verified | Specific terminal apps and versions were not recorded. |

## Bob comparison

Bob documents a shortcut that translates the entire focused input box without a prior text selection, then replaces its contents. It asks users to leave the caret in that input and avoid switching apps during translation. Its [current repository](https://github.com/ripperhe/Bob) says the app is not open source, so its exact Sublime capture and replacement mechanism cannot be established from published code. See [Bob's input-box guide](https://bobtranslate.com/guide/quickstart/translate.html) and [feature announcement](https://bobtranslate.com/blog/2025-08-11-silent-translate.html).

SenseDraft now has a no-plugin, application-agnostic keyboard fallback. It snapshots the active app/window and clipboard, selects and copies the full input only after Analyze, restores the clipboard if its ownership has not changed, and collapses the selection when it cannot restore a saved Accessibility range. In that case the caret moves to the end, which the review panel discloses. Replace requires the user to refocus the same window, compares the entire source again, pastes once, and verifies the result. A clipboard manager may still record the transient copy. This is our implementation, **not a verified description of Bob's internals**. Sublime documents **⌘U** as Undo Selection, which is an option for later refinement; see its [keyboard selection documentation](https://www.sublimetext.com/docs/multiple_selection_with_the_keyboard.html).

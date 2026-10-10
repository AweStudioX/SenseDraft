# Editor compatibility

The table records direct observations from the packaged `SenseDraft.app`. A successful compile is not evidence that a third-party editor supports Accessibility writes.

| App / editor | Read full field | Replace full field | Notes |
| --- | --- | --- | --- |
| TextEdit plain text | Pending manual test | Pending manual test | Native AppKit |
| Safari textarea | Pending manual test | Pending manual test | Browser editor |
| Chrome textarea | Pending manual test | Pending manual test | Browser editor |
| Safari/Chrome contenteditable | Pending manual test | Pending manual test | Rich text may need copy fallback |
| Slack message composer | Pending packaged-app test | Pending packaged-app test | Slack exposes the focused composer as a settable text entry area. SenseDraft now queries Slack's application focus directly when the global focus query is unavailable; live capture and replacement still need confirmation. |
| Sublime Text editor | No | No | In the observed Sublime window, Accessibility exposed the window and title but no readable focused editor value. SenseDraft now reports this explicitly. A Sublime plugin would be needed for direct integration. |

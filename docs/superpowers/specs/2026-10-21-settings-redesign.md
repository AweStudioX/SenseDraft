# SenseDraft settings redesign

## Direction

Use the supplied Bob screenshot as a structural reference: global navigation on the left, a selectable list for the current section, and a focused detail pane on the right. Keep SenseDraft's own macOS system colors and icons. The settings window opens at 1040 × 680 points and can shrink to 900 × 580.

## Navigation and pages

- **Home:** a concise app overview, current AI and permission status, and the formatting-loss replacement switch. Rows link to the relevant settings page.
- **AI:** the middle column lists OpenAI, ChatGPT plan, DeepSeek, and Kimi in their request priority order. Each row shows configured status and an enable switch. Selecting a row opens model, a separate **Show in results** switch, and credential controls in the detail pane. The bottom bar saves AI choices and keys.
- **Writing:** tone, opening case, abbreviation choice, and custom guidance appear as aligned form rows, with short explanations beside the affected control.
- **History:** search and filtering above a selectable history list; the selected entry appears in a detail pane. Saving and retention controls stay visible near the top; delete actions retain confirmation.
- **Shortcuts:** Analyze and Replace appear in a short list; selection shows the recorder and its instructions. Save and restore actions share the bottom bar.
- **Permissions:** a single Accessibility item shows current status and recovery steps in the detail pane. Permission actions are grouped together.

## Credential behavior

Each API source has a secure key field and a separate Remove key action. A saved key appears as fixed mask characters inside the field; the key itself is not read back into the UI. Command-V inserts into the focused field. New keys are written to the existing per-provider Keychain entries when Save AI settings is pressed. A Check connection button sends a fixed sample request to the selected provider and reports success or a concise failure. No key is shown in screenshots or logs.

Kimi includes an API region selector. China uses `api.moonshot.cn`; Global uses `api.moonshot.ai`. China remains the default for existing settings.

## Interaction rules

- Selecting a source does not enable it. The switch controls use; the row controls which details are shown.
- Enabled sources with **Show in results** selected are requested in the order shown. Unconfigured sources are skipped. Existing result-count preferences migrate to the first corresponding enabled sources.
- AI draft values persist across row selection. The fixed bottom save bar keeps the action visible.
- History entry selection does not open a modal. Delete and clear confirmations remain explicit.
- Pages use consistent 8-point spacing, semantic system colors, keyboard focus, and readable labels. Narrow windows scroll the detail content, not the global sidebar.
- AI rows and result choices use bundled provider icons from official brand sources. Saving settings gives visible success or failure feedback.
- The review panel shows the number of results requested out of the available configured sources. Changing that count re-runs the current analysis and saves the count preference.

## Verification

- Build and run all Swift tests.
- Inspect the packaged app at the default and minimum window widths, in light and dark appearance.
- In a disposable preview app, verify a dummy key can be entered with Command-V, a saved key shows only a fixed mask, and switching services preserves an unsaved draft. Do not save the dummy key.
- Check navigation, source selection versus enabling, each source's result switch, history detail, shortcut recorder, and permission status in the packaged app.

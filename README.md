# SenseDraft

<p align="center">
  <img src="Resources/AppIcon.png" alt="SenseDraft woodpecker icon" width="128" height="128">
</p>

<p align="center"><strong>Check the meaning. Then write the English.</strong></p>

<p align="center">先确认原意，再写出自然英文。</p>

SenseDraft is an open-source macOS menu bar app for people who write in English but think in Chinese. Press a shortcut in the text field you are already using: it improves English or translates Chinese into natural English, then shows a Chinese interpretation so you can check whether the result says what you meant. Nothing is sent just because you type, and the app never replaces text before you ask it to.

SenseDraft 是一款 macOS 菜单栏写作工具。在当前输入框按快捷键，即可润色英文或把中文写成自然英文，并通过中文释义核对意思。你可以修改释义后重新生成，确认结果再替换原文。

> **Project status:** Early development. Build from source; no signed download or universal editor compatibility is promised yet. See [editor compatibility](docs/compatibility.md) and the [manual test checklist](docs/manual-testing.md).

## Why SenseDraft?

The writing flow keeps the intended meaning visible:

1. **Analyze the whole focused input.** No text selection is required. Analysis starts only when you press the Analyze shortcut.
2. **Review English alongside a Chinese interpretation.** Keep the original English when it is already natural, or edit the proposed English yourself.
3. **Correct the meaning if needed.** Edit the Chinese interpretation and choose **Regenerate** to get a new English draft without changing the source field.
4. **Replace deliberately.** SenseDraft checks that the original app, field, and complete source text still match before writing. If it cannot verify the target or result, the draft remains available to copy.

## Features

| | Current behavior |
| --- | --- |
| Input | English polishing and Chinese-to-English writing from the complete focused field |
| Review | Editable English draft, Chinese meaning check, regeneration, and explanation when no rewrite is needed |
| Control | Separate, configurable global shortcuts for Analyze and Replace; no background analysis while typing |
| Writing style | Tone, opening capitalization, extra guidance, and English locale settings |
| AI access | Your OpenAI API key or an eligible account using **Sign in with ChatGPT**; credentials stay in macOS Keychain |
| Editor access | Accessibility capture where supported; a shortcut-triggered keyboard fallback for editors that hide their text |
| Replacement | Source verification before writing, result verification afterward, and a copy option when replacement is unavailable |

## Build and try it

Requires **macOS 14+**, **Xcode 26**, and **Swift 6**. There is no prebuilt release yet.

```sh
git clone https://github.com/AweStudioX/SenseDraft.git
cd SenseDraft
./Scripts/build-app.sh
open build/SenseDraft.app
```

On first launch, follow the **Permissions** guide to grant Accessibility access. In **Settings → AI**, choose an OpenAI API key or **ChatGPT plan**, select a model and English locale, and save. ChatGPT plan usage requires an eligible account and is subject to that account's limits; see the [connection guide](docs/chatgpt-plan.md). API credentials are stored in Keychain.

The default shortcuts are **⌘⌥E** for Analyze and **⌘⌥Return** for Replace. You can change or restore them in **Settings → Shortcuts**.

## Use it in an editor

1. Put the caret in an English or Chinese text field and press **Analyze**. You do not need to select text.
2. Check the proposed English against its Chinese interpretation. Edit either one if needed; if you change the Chinese meaning, choose **Regenerate**.
3. For a supported single-line field, click **Replace** or press its shortcut. For multiline editors, return to the original input and use the **Replace shortcut**. Use **Copy English** when the editor does not support a verified replacement.

The review panel normally opens beside the focused input and remembers a position you drag it to. **Escape** closes it without changing the source. If the source changed after analysis, SenseDraft refuses to overwrite it. It asks before replacing text that appears to have mixed formatting, because replacement may remove formatting.

## Privacy and editor limitations

- SenseDraft reads the focused field only after **Analyze** and sends that text to the selected OpenAI model. It does not keep an input/output history.
- A keyboard fallback may briefly select and copy the entire input when an editor does not expose its text through Accessibility. SenseDraft attempts to restore the clipboard, but the caret may move to the end and clipboard-history apps may retain the temporary copy.
- Password and protected fields are excluded. Some editors do not support reliable capture or replacement; SenseDraft offers copying when it cannot safely write.
- Cross-app behavior still needs packaged-app testing. The [compatibility table](docs/compatibility.md) distinguishes observed behavior from pending tests.

For local ad hoc builds, macOS may require a fresh Accessibility grant when the app's code signature changes. If SenseDraft shows **Access needed** despite an enabled entry, quit it, remove the old entry in **System Settings → Privacy & Security → Accessibility**, add the current `build/SenseDraft.app`, and reopen it. `SENSEDRAFT_SIGN_IDENTITY` can be set when building with a stable signing identity.

## Development

```sh
swift test
swift build
./Scripts/build-app.sh
```

`Sources/SenseDraftCore/` holds the analysis and session rules; `Sources/SenseDraftMac/` contains the menu bar app, panel, hotkeys, and Accessibility integration. Logic tests are in `Tests/SenseDraftCoreTests/`. Changes to capture, replacement, permissions, or sign-in also need the [manual test checklist](docs/manual-testing.md), with verified editor results recorded in [compatibility](docs/compatibility.md).

Issues and pull requests are welcome. Please describe the editor and macOS version for integration bugs, and include automated and manual checks for behavior changes. Never include captured text, clipboard contents, API keys, or OAuth tokens in reports.

## License

SenseDraft is available under the [MIT License](LICENSE).

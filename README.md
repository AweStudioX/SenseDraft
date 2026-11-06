# SenseDraft

**English** | [简体中文](README.zh-CN.md)

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white) ![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white) [![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

<p align="center">
  <img src="Resources/AppIcon.png" alt="SenseDraft woodpecker icon" width="128" height="128">
</p>

<p align="center"><strong>Check the meaning. Then write it naturally.</strong></p>

SenseDraft is an open-source macOS menu bar app for writing across languages. Press a shortcut in the text field you are already using: it suggests natural wording in your chosen target language, then shows a meaning check in a second language. The defaults are US English and Simplified Chinese. Nothing is sent just because you type, and the app never replaces text before you ask it to.

> **Project status:** Early development. Build from source; no signed download or universal editor compatibility is promised yet. See [editor compatibility](docs/compatibility.md) and the [manual test checklist](docs/manual-testing.md).

## Why SenseDraft?

The writing flow keeps the intended meaning visible:

1. **Analyze the whole focused input.** No text selection is required. Analysis starts only when you press the Analyze shortcut.
2. **Review English alongside a Chinese interpretation.** Keep the original English when it is already natural, or edit the proposed English yourself.
3. **Correct the meaning if needed.** Edit the meaning check and choose **Regenerate from meaning check**, or press **⌘Return** in the review panel, to get a new draft without changing the source field.
4. **Replace deliberately.** SenseDraft checks that the original app, field, and complete source text still match before writing. If it cannot verify the target or result, the draft remains available to copy.

## Features

| | Current behavior |
| --- | --- |
| Input | Improve wording or write in the chosen target language from the complete focused field |
| Review | Compare results from the AI sources selected in settings; choose one to edit, copy, regenerate, or replace, with a meaning check in the chosen reference language |
| Control | Separate, configurable global shortcuts for Analyze and Replace; no background analysis while typing |
| Writing style | Target and meaning-check languages, tone, English capitalization, and extra guidance |
| AI access | OpenAI, Claude, Gemini, OpenRouter, Qwen, DeepSeek, and Kimi API keys; Ollama and custom OpenAI-compatible endpoints; an optional Apple on-device model; plus an eligible account using **Sign in with ChatGPT**. Credentials stay in macOS Keychain. |
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

On first launch, follow the **Permissions** guide to grant Accessibility access. In **Settings → AI Services**, enable and configure the sources you want, then turn on **Show in results** for each service you want to compare. SenseDraft contacts those selected sources in the order shown. For Kimi and Qwen, choose the API region that matches your key. ChatGPT plan usage requires an eligible account and is subject to that account's limits; see the [connection guide](docs/chatgpt-plan.md). See [AI services](docs/ai-services.md) for the other providers and local model requirements. API credentials are stored in Keychain.

The default global shortcuts are **⌘⌥E** for Analyze and **⌘⌥Return** for Replace. You can change or restore them in **Settings → Shortcuts**. In the review panel, **⌘Return** regenerates the analysis. Press **Escape** or **⌘W** to close Settings; when recording a shortcut, Escape cancels the recording first.

## Use it in an editor

1. Put the caret in an English or Chinese text field and press **Analyze**. You do not need to select text.
2. If multiple results are available, use ↑/↓ in the review panel to select one. Check its suggestion against the meaning check and edit either one if needed. The language menu in Review offers **Write in** and **Check meaning in**; changing either regenerates all results.
3. With the review panel focused outside a text editor, press **Return** to replace the selected result, or click **Replace**. Inside a result editor, Return inserts a newline. For editors where SenseDraft cannot restore focus, return to the original input and use the **Replace shortcut**. Use the footer **Copy** button when the editor does not support a verified replacement.

The review panel normally opens beside the focused input and remembers a position you drag it to. **Escape** closes it without changing the source. If the source changed after analysis, SenseDraft refuses to overwrite it. It asks before replacing text that appears to have mixed formatting, because replacement may remove formatting.

## Privacy and editor limitations

- SenseDraft reads the focused field only after **Analyze** and sends that text to the configured sources used for the current analysis. Encrypted local history is optional and off by default.
- A keyboard fallback may briefly select and copy the entire input when an editor does not expose its text through Accessibility. SenseDraft attempts to restore the clipboard, but the caret may move to the end and clipboard-history apps may retain the temporary copy.
- Password and protected fields are excluded. Some editors do not support reliable capture or replacement; SenseDraft offers copying when it cannot safely write.
- Cross-app behavior still needs packaged-app testing. The [compatibility table](docs/compatibility.md) distinguishes observed behavior from pending tests.

For local ad hoc builds, macOS may require a fresh Accessibility grant when the app's code signature changes. [Set up a stable local signing identity](docs/local-signing.md) once to keep approval across future builds. If SenseDraft shows **Access needed** despite an enabled entry, quit it, remove the old entry in **System Settings → Privacy & Security → Accessibility**, add the current `build/SenseDraft.app`, and reopen it.

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

# SenseDraft

SenseDraft is a macOS menu bar app for improving English while checking the intended meaning in Chinese. It reads the entire focused input when you press Analyze, so you do not need to select text. It never sends text merely because you type. For editors that hide their text from macOS Accessibility, Analyze can briefly select and copy the input, then restore the clipboard; the caret may move to the end. Clipboard-history apps may record this temporary copy.

## Build and launch

Requires macOS 14 or newer and Xcode 26 with Swift 6. Run:

```sh
./Scripts/build-app.sh
open build/SenseDraft.app
```

The first launch opens the Permissions guide. In **AI**, choose either an OpenAI API key or **ChatGPT plan**. The latter opens OpenAI's authorization page in your browser and requires an eligible account; choose a model from that account's catalog after connecting. Set the English locale there. Credentials are stored in macOS Keychain. In **Shortcuts**, record and save Analyze and Replace, or click **Restore defaults** for `⌘⌥E` and `⌘⌥Return`.

Local builds are ad hoc signed by default. macOS ties Accessibility approval to the exact signed code, so a changed build can show an enabled SenseDraft entry while the current app still reports **Access needed**. In that case, quit SenseDraft, remove the old entry from System Settings → Privacy & Security → Accessibility, use **Reveal this app in Finder** to locate the current bundle, add that bundle, enable it, then reopen SenseDraft. The build script preserves the signature when the compiled app has not changed. If you have a stable macOS code signing identity, set `SENSEDRAFT_SIGN_IDENTITY` when running the script to preserve permissions across code changes.

Focus an editable English input field and press Analyze. Review the improved English and Chinese interpretation. If the meaning is wrong, edit the Chinese and click **Regenerate from Chinese**. Press Replace to write the reviewed English back to the original field. If the original has changed, replacement is refused. You can copy the English from the panel when an editor does not support direct replacement.

SenseDraft keeps the original English when it is already natural, and explains why it did not suggest a change. You can also edit the proposed English directly before replacing. If the app detects mixed text formatting, it asks you to confirm that replacement may remove formatting; copying the English is always available. Escape closes the review panel. The ChatGPT sign-in wait can be cancelled from Settings.

## Privacy and current scope

SenseDraft reads the focused field only after Analyze. The input is sent to the selected OpenAI model for analysis; input and output are not saved to a history. Credentials remain in Keychain. The ChatGPT plan path follows OpenAI's Sign in with ChatGPT flow and is subject to the selected account's eligibility and limits. It has automated contract tests but still needs a manual sign-in and live request on an eligible account before it can be called verified.

Cross-app replacement depends on each editor's Accessibility or standard keyboard command behavior. Password and protected fields are excluded. In editors that expose only a window to Accessibility, a copied source cannot always be proven to be an editable input; check the source shown in the panel before using Replace. See `docs/compatibility.md` for the verification status of each app.

For the first manual pass, follow the short checklist in `docs/manual-testing.md`. The app has automated tests for analysis, response handling, shortcuts, and stale-target rules; live Accessibility replacement, API credentials, and ChatGPT authorization still require user testing.

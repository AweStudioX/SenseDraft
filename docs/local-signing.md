# Keep Accessibility and Keychain approval across local builds

macOS ties Accessibility and Keychain approval to the app's code-signing identity. An ad hoc signature changes when the executable changes, so a rebuilt app may need approval again. Use one stable signing certificate for local builds to keep the identity consistent. SenseDraft checks whether API keys exist without reading their secret values and caches keys in memory after the first authorized read in each app run.

## One-time setup

1. Open **Keychain Access → Certificate Assistant → Create a Certificate**.
2. Name it exactly **SenseDraft Local Development**. Choose **Self Signed Root** as the identity type and **Code Signing** as the certificate type. Select **Let me override defaults**, choose a long enough validity period for local development, and accept the remaining defaults. Keep the private key in your login keychain; do not export it into this repository.
3. Confirm `security find-identity -v -p codesigning` lists **SenseDraft Local Development** as a valid identity. If it is not valid, inspect that certificate's trust settings in Keychain Access and trust it for **Code Signing** only. macOS may request your password for this one-time change.
4. Quit SenseDraft, run `./Scripts/build-app.sh`, and reopen `build/SenseDraft.app`. The build script automatically chooses that identity. Grant Accessibility access to this newly signed build once. Later builds signed with the same certificate should keep that approval.

If you already have a suitable Apple Development or Developer ID identity, set `SENSEDRAFT_SIGN_IDENTITY` to its name or SHA-1 hash when building instead. Avoid switching between identities for the same local app: macOS treats them as different code-signing identities.

To keep that choice for later local builds, put the identity name or SHA-1 hash in `build/local-signing-identity.txt`. The build directory is ignored by Git. `SENSEDRAFT_SIGN_IDENTITY` still takes precedence when set.

Check a build with `codesign -dv --verbose=4 build/SenseDraft.app` and `codesign -dr - build/SenseDraft.app`. The signature should no longer say `adhoc`, and the designated requirement should include the same certificate on subsequent builds.

The self-signed certificate is for local development only. Distribution requires an appropriate Apple-issued identity and, where applicable, notarization.

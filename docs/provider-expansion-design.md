# AI service expansion design

## Scope

Add direct Claude and Gemini API access, OpenRouter, Alibaba Cloud Model Studio (Qwen), Ollama, and one configurable OpenAI-compatible endpoint. Add an optional Apple on-device model through Foundation Models when macOS and Apple Intelligence support it. Existing OpenAI, ChatGPT plan, DeepSeek, and Kimi settings remain valid.

## Architecture

- Keep the existing `LanguageService` analysis contract and result validation. Claude uses its Messages API; Gemini, OpenRouter, Qwen, Ollama, and the custom endpoint use an OpenAI-compatible Chat Completions adapter with per-service output format.
- Keep secrets in Keychain. Store only model IDs, region, and endpoint settings in UserDefaults. The custom endpoint accepts HTTPS, or HTTP on loopback for a local server, with an optional key. Never send a key over remote HTTP.
- Show new services in the current settings list, disabled by default. Every service gets a model field and connection check. Ollama needs no key. Apple appears only when its framework is available, with an explicit unavailability reason.
- Limit the results page to enabled services already selected to show results; preserve replacement guards and the current analysis result contract.

## Verification

Use transport-level tests for request endpoints, authentication, body formats, malformed responses, and endpoint validation. Run Swift tests and package the app. Live credentials are not available in the repository, so provider connection checks require users' own keys. Check Apple model availability and supported languages on the running Mac.

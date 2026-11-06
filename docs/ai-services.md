# AI services

SenseDraft sends an explicit Analyze request only to enabled services with **Show in results** turned on. API keys are stored in macOS Keychain. Model IDs, API region, and custom base URL are saved in app preferences. Use **Check connection** after entering a model and key; this sends a short analysis request and may consume provider quota.

| Service | Setup | Interface |
| --- | --- | --- |
| Claude | Anthropic API key and model ID | Native Messages API with structured JSON output |
| Gemini | Google AI API key and model ID | Google OpenAI-compatible Chat Completions endpoint with structured JSON output |
| OpenRouter | OpenRouter API key and model ID | Chat Completions; choose a model/provider endpoint that supports structured output |
| Qwen | Alibaba Cloud Model Studio API key, region, and model ID | OpenAI-compatible Chat Completions endpoint; API keys are region-specific |
| Ollama | Start the local server and install a model; enter its model ID | Local Chat Completions endpoint; no API key |
| Custom endpoint | Enter API base URL, model ID, and optional key | Chat Completions with JSON-object output; supports HTTPS or loopback HTTP only |
| Apple on-device | Enable Apple Intelligence on an eligible Mac running macOS 26 or later | Foundation Models framework; no key and no network request |

The custom URL is a **base URL** such as `https://provider.example/v1` or `http://localhost:1234/v1`; SenseDraft appends `/chat/completions`. A custom endpoint may require provider-specific parameters that this generic adapter does not supply. A successful connection check confirms the configured model can return SenseDraft's full result, not just a plain chat reply.

Apple's on-device model is offered separately from Siri. Its availability depends on the Mac, region, Apple Intelligence state, and model download. It supports only its reported languages and has a relatively small context window; long text may need a cloud service or a shorter selection. On unsupported devices the setting shows the reason and cannot be enabled.

Provider request shapes are covered by transport-level tests. Live connection checks require the user's own keys and an installed Ollama model; they are not part of automated tests.

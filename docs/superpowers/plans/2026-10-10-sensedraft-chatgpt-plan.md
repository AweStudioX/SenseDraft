# SenseDraft ChatGPT Plan Usage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let eligible users authorize SenseDraft to perform text analysis with their ChatGPT plan, while retaining the API Key path when the plan is unavailable.

**Architecture:** Add Sign in with ChatGPT as a second implementation of the core `LanguageService` interface. Keep OAuth credentials in Keychain, discover models for the selected account, and call the public Responses API with the documented plan-use token and streaming contract. This plan starts only after the core app's analysis and replacement loop is verified.

**Tech Stack:** Swift 6.3, AppKit system browser callback, OAuth PKCE, CryptoKit, Security Keychain, URLSession SSE, XCTest.

## Global Constraints

- Use only the official Sign in with ChatGPT flow and public `https://api.openai.com/v1` endpoints. Never read Codex credential files or use private `backend-api` endpoints.
- ChatGPT plan usage is available only when the account, workspace, distribution model, permission, and current OpenAI policy allow it. Surface ineligibility without silently switching billing paths.
- For this route, set `store: false` and `stream: true`, send the full required context in `input`, and treat only `response.completed` as success.
- Keep OAuth access and refresh tokens in Keychain; do not log tokens, input text, or output text.
- Keep the API Key option available and clearly label which billing path is active.

## File map

| File | Responsibility |
| --- | --- |
| `Sources/SenseDraftCore/ChatGPTPlanProvider.swift` | Plan-use Responses API and model discovery |
| `Sources/SenseDraftCore/StreamDecoder.swift` | SSE completion and error interpretation |
| `Sources/SenseDraftMac/ChatGPTAuth.swift` | OAuth registration, PKCE, callback, token refresh |
| `Sources/SenseDraftMac/AccountStore.swift` | Keychain-backed account and host ID records |
| `Sources/SenseDraftMac/ProviderSettings.swift` | Connect, disconnect, provider choice and status |
| `Tests/SenseDraftCoreTests/StreamDecoderTests.swift` | Success only after completed event |
| `Tests/SenseDraftCoreTests/ChatGPTPlanProviderTests.swift` | Request contract and error interpretation |
| `docs/chatgpt-plan.md` | Eligibility and user setup |

---

### Task 1: Streaming response contract

**Files:** Create `Sources/SenseDraftCore/StreamDecoder.swift`, `Tests/SenseDraftCoreTests/StreamDecoderTests.swift`.

**Interfaces:** `StreamDecoder.consume(_ lines: [String]) throws -> String`; errors `failed(code: String)`, `incomplete`, `interrupted`.

- [ ] Write tests using literal SSE frames: text deltas followed by `response.completed` produce final text; identical deltas without completion throw `interrupted`; `response.failed` with `subscription_sharing_usage_limit_exceeded` throws the exact code. Run `swift test --filter StreamDecoderTests` and verify expected compile failure.
- [ ] Parse `data:` JSON frames, accumulate `response.output_text.delta`, require terminal `response.completed`, and map failure/incomplete terminal events. Run the focused tests and full `swift test`; expect pass. Commit as `feat: decode completed plan responses`.

### Task 2: OAuth registration and account storage

**Files:** Create `Sources/SenseDraftMac/ChatGPTAuth.swift`, `Sources/SenseDraftMac/AccountStore.swift`, `Tests/SenseDraftCoreTests/AuthStateTests.swift`, `Sources/SenseDraftCore/AuthState.swift`.

**Interfaces:** `AuthState` distinguishes disconnected, identity-only, plan-enabled, expired, and ineligible. `ChatGPTAuth.signIn() async throws -> PlanAccount`; `ChatGPTAuth.refresh(_:) async throws -> PlanAccount`.

- [ ] Write tests for scope interpretation: a valid identity without `chatgpt.tokens.use.direct` is identity-only, and only the granted direct-use scope enables inference. Run the focused tests and verify red.
- [ ] Implement pure scope parsing, then the documented dynamic-client authorization using persistent `ext_agent_host_id`, state, nonce, PKCE, system browser, loopback callback, authorization-code exchange, and ID token verification. Save the issued `client_id` before token exchange. Persist tokens and account identifiers in Keychain and refresh before expiration. Never use an API Key as a substitute without user selection.
- [ ] Run `swift test` and `swift build`; expect pass. Manually sign in with an eligible test account and verify the granted scopes in the UI without printing tokens. Commit as `feat: authorize ChatGPT plan usage`.

### Task 3: Account-specific models and inference

**Files:** Create `Sources/SenseDraftCore/ChatGPTPlanProvider.swift`, `Tests/SenseDraftCoreTests/ChatGPTPlanProviderTests.swift`.

**Interfaces:** `ChatGPTPlanProvider` implements `LanguageService`; `listModels() async throws -> [PlanModel]` returns visible account models with exact `slug` values.

- [ ] Write transport-backed tests that assert `GET /v1/models` uses the OAuth access token and selects only visible models; `POST /v1/responses` uses an allowed model, `store: false`, `stream: true`, an `input` array, and no unsupported preview fields. Test exhausted usage and non-completed streams. Run and verify red.
- [ ] Implement model discovery and streaming inference through the public Responses API. Build instructions for the same analysis result as the API Key provider. Parse and validate the final structured result only after `response.completed`. Surface exact usage and eligibility errors.
- [ ] Run focused and full tests plus `swift build`; expect pass. Verify a real short English sentence and Chinese interpretation using the authorized account. Commit as `feat: analyze with ChatGPT plan`.

### Task 4: Provider selection and recovery UI

**Files:** Create `Sources/SenseDraftMac/ProviderSettings.swift`, modify `Sources/SenseDraftMac/SenseDraftApp.swift`, `Sources/SenseDraftMac/Panel.swift`, and create `docs/chatgpt-plan.md`.

**Interfaces:** Settings exposes `API Key` and `ChatGPT plan` choices, connected account, model, usage management link, reconnect, and disconnect.

- [ ] Add a pure provider-selection test so that switching providers changes the selected service for the next analysis and never silently changes the provider after an error. Run and verify red.
- [ ] Add the settings screen and account actions. When plan access is denied, expired, exhausted, or unavailable, preserve the source and show an actionable message. Require explicit user selection before any API Key fallback. Document eligible project types and the current preview limitations.
- [ ] Run `swift test`, `swift build`, and bundle verification. Manually test connect, analyze, revoke/reconnect, exhausted usage handling, and switching back to API Key. Commit as `feat: expose plan provider settings`.

## Review gate

Only claim this path works after an eligible real account completes a request and an ineligible or revoked account produces a clear failure without changing the source. Recheck the official documentation before implementation because this integration is in preview and eligibility or request requirements can change.

## Official references

- https://developers.openai.com/siwc/quickstart
- https://developers.openai.com/siwc/token-sharing-open-source
- https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference
- https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations
- https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery

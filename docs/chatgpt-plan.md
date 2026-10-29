# ChatGPT plan connection

In Settings → AI, enable **ChatGPT plan** and click **Continue with ChatGPT**. SenseDraft opens `auth.openai.com` in the system browser, receives the authorization result on a local loopback address, verifies the signed OpenAI identity token, and stores the issued credentials in macOS Keychain. It then loads the models available to the authorized account. ChatGPT plan is included in an analysis only when connected and within the chosen result count; other enabled API sources use their own credentials and billing.

The browser's local callback page means only that SenseDraft received the authorization response. Check the AI settings status for token exchange and account verification. If token exchange fails, SenseDraft shows the HTTP status and OAuth error code; start a fresh sign-in because authorization codes are single use. An account can remain connected even if the later model-list request fails; use **Refresh models** after the service recovers.

OpenAI currently describes this route for eligible Plus and Pro accounts in open-source or local apps. The user must grant `chatgpt.tokens.use.direct`; identity-only sign-in is insufficient. Usage is subject to the account and workspace limits. SenseDraft uses the public Responses API with `store: false` and `stream: true`, and requires a `response.completed` event before accepting output. Disconnect removes the locally stored account credential.

This integration is not yet live-tested with a consenting eligible account. If authorization, model discovery, or inference fails, use the error shown in the panel or Settings. The API Key route is separately available by explicit selection.

Official sources: [Quickstart](https://developers.openai.com/siwc/quickstart), [Registration and sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in), [Models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference).

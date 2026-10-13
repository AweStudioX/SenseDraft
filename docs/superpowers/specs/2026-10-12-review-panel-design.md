# SenseDraft review panel refresh

Date: 2026-10-12

## Scope

Replace succeeds only after the app verifies the original field. On success, close the review panel and clear the session. On failure, retain the panel and candidate with a visible error.

The existing AI tab gains a Writing preferences section without adding another top-level tab. Three styles cover Natural (default, idiomatic everyday English), Casual (brief conversation), and Professional (clear workplace language). Opening case can follow the input, request a lowercase opening, or use standard capitalization; proper names and the pronoun “I” stay capitalized. An optional short custom instruction can guide wording without overriding the source's meaning, names, numbers, or uncertainty. These preferences are sent in both API key and ChatGPT plan requests. Changing a preference never sends a request automatically; the next analysis or regeneration applies it. Regeneration uses edited Chinese as authoritative only when the user changed the interpretation.

## Panel design

Use a compact native macOS utility style: system typography, semantic surfaces, restrained blue accent, short source reference, editable English candidate, editable Chinese meaning, and a fixed action area. Writing preferences do not appear in the review panel. Let the content extend into the hidden title bar so no empty top strip remains; hide the traffic light controls and close the focused panel with Escape. Keep the default window short, with scrollable content for longer text and a visible action area. Avoid repeating the no-change message, and only present Replace as available when the English differs from the source. Loading, capture failure, ambiguity, keyboard fallback, and formatting risk remain visible. Support light/dark appearance and keyboard focus.

This iteration applies the visual system only to the review panel. The AI tab uses the existing Settings visual style and scrolls to fit the added writing controls; a broader Settings redesign waits for the user's panel style approval.

## Validation

Add tests for preference instructions and meaning preservation, run the complete Swift suite, build/sign the app, and inspect a rendered panel state where possible. Cross-app replacement remains a manual integration check.

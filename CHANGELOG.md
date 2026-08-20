# Changelog

## 3.12.0

### Changed

- **`OmniAI::Chat::Usage#output_tokens` now includes thinking tokens on Gemini thinking models.** Gemini reports the answer as `candidatesTokenCount` and internal reasoning separately as `thoughtsTokenCount`, and bills both as output. This gem previously read `candidatesTokenCount` alone, so `output_tokens` excluded reasoning and understated billable output — substantially, since thinking is on by default on Gemini 3.x flash models. `output_tokens` is now `candidatesTokenCount + thoughtsTokenCount`, matching Anthropic and OpenAI, where reasoning is already counted in the output total and reported back only as a breakdown.

  **If you were adding `thoughtsTokenCount` yourself to compensate, remove it** — otherwise reasoning is counted twice. There is no error to catch: the number is simply wrong.

  The reasoning subset is available as `Usage#thinking_tokens`, and the raw `thoughtsTokenCount` remains reachable verbatim on `response.data`. Requires omniai >= 3.8.

  This also restores an invariant the gem previously broke: `totalTokenCount` always included thinking, so `input_tokens + output_tokens` did not equal `total_tokens` on any thinking response. It now does.

### Fixed

- `OmniAI::Chat::Usage#serialize` emits `thoughtsTokenCount` and splits inclusive `output_tokens` back into `candidatesTokenCount`, so a usage payload round-trips. It previously wrote `output_tokens` into `candidatesTokenCount` and dropped the reasoning count entirely, making serialization lossy in both directions. The key is omitted when no reasoning is reported, matching Gemini, so payloads for non-thinking responses are unchanged.

Earlier changes are recorded in the GitHub releases.

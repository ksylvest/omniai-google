# Changelog

## 3.14.1

### Fixed

- **A streamed generation that never completes now raises instead of returning the fragment as an answer.** Two ways it happened, both observed in production on `gemini-3.7-flash` and both silent:

  1. Google reports a failure occurring *after* the 200 by putting an `error` object in the stream. `Stream#process_data!` copies every non-candidate key into the aggregate, so that error landed in `data["error"]` and the caller received an empty, **successful** response for an upstream outage. Reproduced: a `503 UNAVAILABLE` arriving mid-stream yielded `text == ""`, `finish_reason == nil`, and no exception anywhere. Now raises `OmniAI::Google::StreamError` carrying Google's code, status and message.

  2. The stream closes cleanly with no terminal chunk **and the candidate produced nothing but thinking** — every part `thought: true`, no answer text, no function call. Downstream this read as "the model returned nothing" rather than "the generation was cut off". Now raises `OmniAI::Google::IncompleteStreamError`.

  **A missing `finishReason` on its own is not enough to raise, and treating it as enough would be worse than the bug.** Measured in production, in the same conversation and hour and model as the failures above: a turn delivered a complete 33,732-character answer with no finish reason at all. Raising on that would discard the one turn that worked and spend the retry budget re-running it. So a stream that ends unterminated but carries text or a tool call is returned as before, with `finish_reason` left `nil` — not fabricated into a `STOP`, since an unterminated-but-substantive stream is a fact about the response and hiding it would be the same laundering this guard exists to stop. Callers who want to alert on it can check `finish_reason.nil?` with text present.

  Neither error carries a `#response`, deliberately: the request succeeded with a 200 and the failure arrived inside the stream, so there is no HTTP response to attach. It also matters downstream — consumers commonly branch on whether an error exposes a response to separate "the server answered and said no" (do not retry) from "the call did not complete" (retry). A stream that stopped early is the second kind and is worth retrying. `IncompleteStreamError < StreamError`, so rescue `StreamError` to catch both.

  Error messages carry **structure only** — candidate count, part count, thought-part count, finish reasons seen — never part text, which may be sensitive in the documents these streams carry.

  Unchanged: `MAX_TOKENS` and `SAFETY` still return normally. Those report how a generation ended and are the caller's decision; this guards only streams that never reported at all. This is not transport truncation, which `http.rb` already raises on.

### Note for anyone upgrading from 3.13.x

**3.14.1 carries the `GEMINI_FLASH` alias float from 3.14.0** — the alias resolves to `gemini-3.8-flash`, not `gemini-3.7-flash`. If you resolve models through the alias (including by omitting `model:`), taking this streaming fix also moves your model. Pin `Model::GEMINI_3_7_FLASH` to take the fix without the float, and see the 3.14.0 entry for the pricing-table warning that goes with it.

## 3.14.0

### Added

- `Model::GEMINI_3_8_FLASH` (`"gemini-3.8-flash"`), GA upstream as of 2026-09-02. Verified live against Vertex: the id is listed in the publisher catalog in both `global` and `us-central1`, and a `generateContent` round-trip through this gem returns text and usage. There is no `-preview` suffix on this one, unlike the `gemini-3-flash-preview` / `gemini-3.1-pro-preview` ids.

### Changed

- **`GEMINI_FLASH` now points at `GEMINI_3_8_FLASH` (was `GEMINI_3_7_FLASH`), so `DEFAULT_MODEL` moves to `gemini-3.8-flash`.**

  This moves **two** kinds of caller, and the second is the one that surprises people:

  1. Anyone who omits `model:` — `DEFAULT_MODEL` is defined as `Model::GEMINI_FLASH`.
  2. **Anyone who passes `model: OmniAI::Google::Chat::Model::GEMINI_FLASH` explicitly.** The alias is not a pin. Naming it in your code reads like a choice and behaves like a subscription: it re-points on every minor release that floats it, including this one.

  Pin `Model::GEMINI_3_7_FLASH` — or any versioned constant — to stay where you are. If you resolve models through the alias anywhere that matters, this is the release to switch to an explicit constant.

  **If you keep a per-model pricing or cost table, add a `gemini-3.8-flash` row before you upgrade.** A float onto a model your table does not know about does not raise — it yields a nil price and renders as unpriced, so the first symptom is a billing report that looks wrong rather than an error anyone can catch.

  **Expect the same prompt to cost more.** 3.8 Flash is a thinking model, and since 3.12.0 `Usage#output_tokens` includes `thoughtsTokenCount`. Two independent measurements, at identical list rates:

  - On a one-word answer, 3.8 spent 106 thinking tokens against 3.7's 63 (a third run: 84). One prompt, not a benchmark.
  - On a production page-extraction workload, **3.8 at default cost 1.43x per page versus 3.7**, with thinking accounting for roughly 85% of output tokens.

  List price per token is unchanged from 3.7's introductory rate, so this is entirely a token-volume effect. Budget for it before you float, particularly on high-volume per-page work where a 1.43x on output is the whole margin.

## 3.13.0

### Fixed

- A client constructed with Vertex arguments now resolves the correct API version. `Client#initialize` defaulted `version:` to `OmniAI::Google.config.version`, which derives from the *config's* host rather than the client's, so a Vertex client built from constructor arguments inherited `v1beta` and produced `/v1beta/projects/.../locations/...` — a path that 404s against every regional Vertex endpoint. Callers had to pass `version: "v1"` explicitly for constructor-configured Vertex to work at all.

  Only the Vertex case is derived from the client's own host, via the existing `vertex?` predicate. Any other custom host — a proxy or gateway in front of the Gemini API — continues to defer to the configured version, so those callers are not silently moved off the version they were using. An explicit `version:` still wins in all cases.

  Note for anyone hitting the same 404: the regional host must also match the region in the path (`https://us-central1-aiplatform.googleapis.com` with `locations/us-central1`). That is deliberately not derived, because `locations/global` against the global host is a valid combination.

## 3.12.0

### Changed

- **`OmniAI::Chat::Usage#output_tokens` now includes thinking tokens on Gemini thinking models.** Gemini reports the answer as `candidatesTokenCount` and internal reasoning separately as `thoughtsTokenCount`, and bills both as output. This gem previously read `candidatesTokenCount` alone, so `output_tokens` excluded reasoning and understated billable output — substantially, since thinking is on by default on Gemini 3.x flash models. `output_tokens` is now `candidatesTokenCount + thoughtsTokenCount`, matching Anthropic and OpenAI, where reasoning is already counted in the output total and reported back only as a breakdown.

  **If you were adding `thoughtsTokenCount` yourself to compensate, remove it** — otherwise reasoning is counted twice. There is no error to catch: the number is simply wrong.

  The reasoning subset is available as `Usage#thinking_tokens`, and the raw `thoughtsTokenCount` remains reachable verbatim on `response.data`. Requires omniai >= 3.8.

  This also restores an invariant the gem previously broke. On responses whose `usageMetadata` reports only `promptTokenCount`, `candidatesTokenCount` and `thoughtsTokenCount`, `totalTokenCount` is the sum of the three — so `input_tokens + output_tokens` now equals `total_tokens`, where before it could not. Verified live against Vertex on both the streaming and non-streaming paths. Note the scope: `totalTokenCount` also carries buckets this serializer does not read, such as `toolUsePromptTokenCount` on tool-use responses, and the invariant is not claimed for those.

- `UsageSerializer.deserialize` returns `nil` when the payload carries no token counts at all, so `response.usage` can now be `nil` where it previously was a `Usage` with every field `nil`. Gemini sends a `usageMetadata` on every streamed chunk carrying only `trafficType` and populates the counts solely on the terminal chunk, so a stream that ends early assembles a payload whose key is present but whose counts never arrived. Presence of the key is not presence of usage.

  This does not introduce a new class of `nil`: `response.usage` is already `nil` whenever `usageMetadata` is absent entirely, so consumers that work today already nil-check. It makes an existing `nil` more frequent — and for a billing number a loud `nil` is better than an all-`nil` `Usage` that arithmetic silently turns into zero. The test is strictly "no count present", never "counts are falsy"; a reported `0` is a count and still builds a `Usage`.

### Fixed

- `OmniAI::Chat::Usage#serialize` emits `thoughtsTokenCount` and splits inclusive `output_tokens` back into `candidatesTokenCount`, so a usage payload round-trips. It previously wrote `output_tokens` into `candidatesTokenCount` and dropped the reasoning count entirely, making serialization lossy in both directions. The key is omitted when no reasoning is reported, matching Gemini, so payloads for non-thinking responses are unchanged.

Earlier changes are recorded in the GitHub releases.

# Changelog

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

# frozen_string_literal: true

module OmniAI
  module Google
    class Chat
      # Overrides usage serialize / deserialize.
      module UsageSerializer
        # Gemini reports thinking separately from the answer: `candidatesTokenCount` covers the answer only, while
        # `thoughtsTokenCount` covers internal reasoning. Google bills both as output and `totalTokenCount` includes
        # both, so `output_tokens` is the sum — matching Anthropic and OpenAI, where reasoning is already folded into
        # the output count and reported back only as a breakdown.
        #
        # @param usage [OmniAI::Chat::Usage]
        # @return [Hash]
        def self.serialize(usage, *)
          thinking_tokens = usage.thinking_tokens
          candidates_tokens = usage.output_tokens
          # `thinking_tokens` is a subset of `output_tokens`, so this cannot go negative for any Usage this gem
          # builds. Clamp anyway: a hand-constructed Usage that violates the subset invariant should not produce a
          # negative token count on the wire.
          candidates_tokens = [candidates_tokens - thinking_tokens, 0].max if candidates_tokens && thinking_tokens

          data = {
            promptTokenCount: usage.input_tokens,
            candidatesTokenCount: candidates_tokens,
            totalTokenCount: usage.total_tokens,
          }
          # Gemini omits the key entirely when nothing was thought; only emit it when there is a value to report.
          data[:thoughtsTokenCount] = thinking_tokens unless thinking_tokens.nil?
          data
        end

        # Returns `nil` when the payload carries no token counts at all. A truncated stream still assembles a
        # `usageMetadata` — Gemini sends one on every chunk, carrying only `trafficType` until the terminal chunk —
        # so the presence of the key is not the presence of usage. Building a Usage from it would report every
        # count as `nil`, which arithmetic downstream silently turns into zero.
        #
        # The test is strictly "no count is present", never "the counts are falsy": a reported `0` is a count.
        #
        # @param data [Hash]
        # @return [OmniAI::Chat::Usage, nil]
        def self.deserialize(data, *)
          input_tokens = data["promptTokenCount"]
          candidates_tokens = data["candidatesTokenCount"]
          thinking_tokens = data["thoughtsTokenCount"]
          total_tokens = data["totalTokenCount"]

          return if [input_tokens, candidates_tokens, thinking_tokens, total_tokens].all?(&:nil?)

          output_tokens = (candidates_tokens || 0) + (thinking_tokens || 0) if candidates_tokens || thinking_tokens

          OmniAI::Chat::Usage.new(input_tokens:, output_tokens:, total_tokens:, thinking_tokens:)
        end
      end
    end
  end
end

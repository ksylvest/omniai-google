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
          candidates_tokens -= thinking_tokens if candidates_tokens && thinking_tokens

          data = {
            promptTokenCount: usage.input_tokens,
            candidatesTokenCount: candidates_tokens,
            totalTokenCount: usage.total_tokens,
          }
          # Gemini omits the key entirely when nothing was thought; only emit it when there is a value to report.
          data[:thoughtsTokenCount] = thinking_tokens unless thinking_tokens.nil?
          data
        end

        # @param data [Hash]
        # @return [OmniAI::Chat::Usage]
        def self.deserialize(data, *)
          input_tokens = data["promptTokenCount"]
          candidates_tokens = data["candidatesTokenCount"]
          thinking_tokens = data["thoughtsTokenCount"]
          total_tokens = data["totalTokenCount"]

          output_tokens = (candidates_tokens || 0) + (thinking_tokens || 0) if candidates_tokens || thinking_tokens

          OmniAI::Chat::Usage.new(input_tokens:, output_tokens:, total_tokens:, thinking_tokens:)
        end
      end
    end
  end
end

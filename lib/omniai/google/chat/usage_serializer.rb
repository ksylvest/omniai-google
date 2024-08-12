# frozen_string_literal: true

module OmniAI
  module Google
    class Chat
      # Overrides usage serialize / deserialize.
      module UsageSerializer
        # @param usage [OmniAI::Chat::Usage]
        # @return [Hash]
        def self.serialize(usage, *)
          {
            prompt_token_count: usage.input_tokens,
            candidates_token_count: usage.output_tokens,
            total_token_count: usage.total_tokens,
          }
        end

        # @param data [Hash]
        # @return [OmniAI::Chat::Usage]
        def self.deserialize(data, *)
          input_tokens = data['prompt_token_count']
          output_tokens = data['candidates_token_count']
          total_tokens = data['total_token_count']
          OmniAI::Chat::Usage.new(input_tokens:, output_tokens:, total_tokens:)
        end
      end
    end
  end
end

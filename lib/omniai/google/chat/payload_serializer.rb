# frozen_string_literal: true

module OmniAI
  module Google
    class Chat
      # Overrides payload serialize / deserialize.
      module PayloadSerializer
        # @param payload [OmniAI::Chat::Payload]
        # @param context [OmniAI::Context]
        # @return [Hash]
        def self.serialize(payload, context:)
          candidates = payload.choices.map { |choice| choice.serialize(context:) }
          usage_metadata = payload.usage&.serialize(context:)

          {
            candidates:,
            usage_metadata:,
          }
        end

        # @param data [Hash]
        # @param context [OmniAI::Context]
        # @return [OmniAI::Chat::Payload]
        def self.deserialize(data, context:)
          choices = data['candidates'].map { |candidate| OmniAI::Chat::Choice.deserialize(candidate, context:) }
          usage = OmniAI::Chat::Usage.deserialize(data['usage_metadata'], context:) if data['usage_metadata']

          OmniAI::Chat::Payload.new(choices:, usage:)
        end
      end
    end
  end
end

# frozen_string_literal: true

module OmniAI
  module Google
    class Chat
      # Overrides content serialize / deserialize.
      module ContentSerializer
        # @param data [Hash]
        # @param context [Context]
        # @return [OmniAI::Chat::Text, OmniAI::Chat::Thinking, OmniAI::Chat::ToolCall]
        def self.deserialize(data, context:)
          case
          when data["thought"] then OmniAI::Chat::Thinking.deserialize(data, context:)
          when data["text"] then data["text"]
          when data["functionCall"] then OmniAI::Chat::ToolCall.deserialize(data, context:)
          end
        end
      end
    end
  end
end

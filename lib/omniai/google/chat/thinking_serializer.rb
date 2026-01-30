# frozen_string_literal: true

module OmniAI
  module Google
    class Chat
      # Overrides thinking serialize / deserialize.
      module ThinkingSerializer
        # @param data [Hash]
        # @param context [Context]
        #
        # @return [OmniAI::Chat::Thinking]
        def self.deserialize(data, context: nil) # rubocop:disable Lint/UnusedMethodArgument
          # Google uses "thought: true" as a flag, with content in "text"
          OmniAI::Chat::Thinking.new(data["text"])
        end

        # @param thinking [OmniAI::Chat::Thinking]
        # @param context [Context]
        #
        # @return [Hash]
        def self.serialize(thinking, context: nil) # rubocop:disable Lint/UnusedMethodArgument
          { thought: true, text: thinking.thinking }
        end
      end
    end
  end
end

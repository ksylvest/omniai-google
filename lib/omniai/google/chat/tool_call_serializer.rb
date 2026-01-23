# frozen_string_literal: true

module OmniAI
  module Google
    class Chat
      # Overrides tool-call serialize / deserialize.
      module ToolCallSerializer
        # @param tool_call [OmniAI::Chat::ToolCall]
        # @param context [OmniAI::Context]
        # @return [Hash]
        def self.serialize(tool_call, context:)
          result = { functionCall: tool_call.function.serialize(context:) }
          result[:thoughtSignature] = tool_call.options[:thought_signature] if tool_call.options[:thought_signature]
          result
        end

        # @param data [Hash]
        # @param context [OmniAI::Context]
        # @return [OmniAI::Chat::ToolCall]
        def self.deserialize(data, context:)
          function = OmniAI::Chat::Function.deserialize(data["functionCall"], context:)
          options = { thought_signature: data["thoughtSignature"] }.compact
          OmniAI::Chat::ToolCall.new(id: function.name, function:, **options)
        end
      end
    end
  end
end

# frozen_string_literal: true

module OmniAI
  module Google
    class Chat
      # Overrides tool-call result serialize / deserialize.
      module ToolCallResultSerializer
        # @param tool_call_response [OmniAI::Chat::ToolCallResult]
        # @return [Hash]
        def self.serialize(tool_call_response, *)
          result = {
            functionResponse: {
              name: tool_call_response.tool_call_id,
              response: {
                name: tool_call_response.tool_call_id,
                content: tool_call_response.content,
              },
            },
          }

          thought_signature = tool_call_response.options[:thought_signature]
          result[:thoughtSignature] = thought_signature if thought_signature
          result
        end

        # @param data [Hash]
        # @return [ToolCallResult]
        def self.deserialize(data, *)
          tool_call_id = data["functionResponse"]["name"]
          content = data["functionResponse"]["response"]["content"]
          OmniAI::Chat::ToolCallResult.new(content:, tool_call_id:)
        end
      end
    end
  end
end

# frozen_string_literal: true

module OmniAI
  module Google
    class Chat
      # Overrides tool-call result serialize / deserialize.
      module ToolCallResultSerializer
        # A result whose content is media (e.g. an image) is sent as a multimodal function response part.
        #
        # @param tool_call_response [OmniAI::Chat::ToolCallResult]
        # @return [Hash]
        def self.serialize(tool_call_response, *)
          name = tool_call_response.tool_call_id
          content = tool_call_response.content

          result = {
            functionResponse:
              if content.is_a?(OmniAI::Chat::Media)
                { name:, response: { name: }, parts: [MediaSerializer.serialize(content)] }
              else
                { name:, response: { name:, content: } }
              end,
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
          options = { thought_signature: data["thoughtSignature"] }.compact
          OmniAI::Chat::ToolCallResult.new(content:, tool_call_id:, **options)
        end
      end
    end
  end
end

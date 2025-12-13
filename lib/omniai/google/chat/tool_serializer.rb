# frozen_string_literal: true

module OmniAI
  module Google
    class Chat
      # Overrides tool serialize / deserialize.
      module ToolSerializer
        # @param tool [OmniAI::Tool]
        def self.serialize(tool, *)
          {
            name: tool.name,
            description: tool.description,
            parameters:
              if tool.parameters.is_a?(OmniAI::Schema::Object)
                tool.parameters.serialize(additional_properties: nil)
              else
                tool.parameters
              end,
          }
        end
      end
    end
  end
end

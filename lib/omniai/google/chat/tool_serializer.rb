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
            parameters: tool.parameters&.prepare,
          }
        end
      end
    end
  end
end

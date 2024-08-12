# frozen_string_literal: true

module OmniAI
  module Google
    class Chat
      # Overrides media serialize / deserialize.
      module MediaSerializer
        # @param media [OmniAI::Chat::Media]
        # @return [Hash]
        def self.serialize(media, *)
          {
            inlineData: {
              mimeType: media.type,
              data: media.data,
            },
          }
        end
      end
    end
  end
end

# frozen_string_literal: true

module OmniAI
  module Google
    class Chat
      # Overrides media serialize / deserialize.
      module MediaSerializer
        # @param media [OmniAI::Chat::Media]
        #
        # @return [hash]
        def self.serialize_as_file_data(media)
          {
            fileData: {
              mimeType: media.type,
              fileUri: media.uri,
            },
          }
        end

        # @param media [OmniAI::Chat::Media]
        #
        # @return [hash]
        def self.serialize_as_inline_data(media)
          {
            inlineData: {
              mimeType: media.type,
              data: media.data,
            },
          }
        end

        # @param media [OmniAI::Chat::Media]
        #
        # @return [Hash]
        def self.serialize(media, *)
          if media.is_a?(OmniAI::Chat::URL)
            serialize_as_file_data(media)
          else
            serialize_as_inline_data(media)
          end
        end
      end
    end
  end
end

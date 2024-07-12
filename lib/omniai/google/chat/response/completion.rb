# frozen_string_literal: true

module OmniAI
  module Google
    class Chat
      module Response
        # A completion returned by the API.
        class Completion < OmniAI::Chat::Response::Completion
          # @return [Array<OmniAI::Chat::Choice>]
          def choices
            @choices ||= [].tap do |entries|
              @data['candidates'].each do |candidate|
                candidate['content']['parts'].each do |part|
                  entries << OmniAI::Chat::Response::MessageChoice.new(data: {
                    'index' => candidate['index'],
                    'message' => {
                      'role' => candidate['content']['role'],
                      'content' => part['text'],
                    },
                  })
                end
              end
            end
          end
        end
      end
    end
  end
end

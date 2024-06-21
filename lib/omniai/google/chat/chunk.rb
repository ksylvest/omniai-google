# frozen_string_literal: true

module OmniAI
  module Google
    class Chat
      # A chunk given when streaming.
      class Chunk < OmniAI::Chat::Chunk
        # @return [Array<OmniAI::Chat::Choice>]
        def choices
          @choices ||= [].tap do |choices|
            @data['candidates'].each do |candidate|
              candidate['content']['parts'].each do |part|
                choices << OmniAI::Chat::DeltaChoice.for(data: {
                  'index' => candidate['index'],
                  'delta' => { 'role' => candidate['content']['role'], 'content' => part['text'] },
                })
              end
            end
          end
        end
      end
    end
  end
end

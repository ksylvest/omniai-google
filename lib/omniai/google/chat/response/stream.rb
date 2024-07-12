# frozen_string_literal: true

module OmniAI
  module Google
    class Chat
      module Response
        # A stream given when streaming.
        class Stream < OmniAI::Chat::Response::Stream
          # @yield [OmniAI::Chat::Chunk]
          def stream!(&)
            @response.body.each do |chunk|
              @parser.feed(chunk) do |_, data|
                yield(Chunk.new(data: JSON.parse(data)))
              end
            end
          end
        end
      end
    end
  end
end

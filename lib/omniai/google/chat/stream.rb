# frozen_string_literal: true

module OmniAI
  module Google
    class Chat
      # Combine chunks into a hash. For each chunk yield the text (delta) if a block is given and the chunk is text.
      class Stream < OmniAI::Chat::Stream
        # @yield [delta]
        # @yieldparam delta [OmniAI::Chat::Delta]
        #
        # @return [Hash]
        def stream!(&block)
          @data = { "candidates" => [] }

          @chunks.each do |chunk|
            parser.feed(chunk) do |type, data, id|
              process!(type, data, id, &block)
            end
          end

          @data
        end

      protected

        # @yield [delta]
        # @yieldparam delta [OmniAI::Chat::Delta]
        #
        # @param type [String]
        # @param data [String]
        # @param id [String]
        def process!(type, data, id, &)
          log(type, data, id)

          process_data!(data: JSON.parse(data), &)
        end

        # @yield [delta]
        # @yieldparam delta [OmniAI::Chat::Delta]
        #
        # @param data [Hash]
        def process_data!(data:, &block)
          data.each do |key, value|
            @data[key] = value unless key.eql?("candidates")
          end

          data["candidates"].each_with_index do |candidate, index|
            process_candidate!(candidate:, index:, &block)
          end
        end

        # @yield [delta]
        # @yieldparam delta [OmniAI::Chat::Delta]
        #
        # @param candidate [Hash]
        # @param index [Integer]
        def process_candidate!(candidate:, index:, &block)
          parts = candidate["content"]["parts"]
          return unless parts

          candidate["content"]["parts"].each do |part|
            block&.call(OmniAI::Chat::Delta.new(text: part["text"])) if part["text"]
          end

          merge_candidate!(candidate:, index:)
        end

        # @param candidate [Hash]
        # @param index [Integer]
        def merge_candidate!(candidate:, index:)
          if @data["candidates"][index].nil?
            @data["candidates"][index] = candidate
          else
            merge_parts!(content: @data["candidates"][index]["content"], parts: candidate["content"]["parts"])
          end
        end

        # @param content [Hash]
        # @param parts [Array<Hash>]
        def merge_parts!(content:, parts:)
          parts.each_with_index do |part, index|
            if content["parts"][index].nil?
              content["parts"][index] = part
            else
              content["parts"][index]["text"] += part["text"]
            end
          end
        end
      end
    end
  end
end

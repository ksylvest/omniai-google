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

          data["candidates"]&.each_with_index do |candidate, index|
            process_candidate!(candidate:, index:, &block)
          end
        end

        # @yield [delta]
        # @yieldparam delta [OmniAI::Chat::Delta]
        #
        # @param candidate [Hash]
        # @param index [Integer]
        def process_candidate!(candidate:, index:, &block)
          candidate.dig("content", "parts")&.each do |part|
            if part["thought"]
              block&.call(OmniAI::Chat::Delta.new(thinking: part["text"]))
            elsif part["text"]
              block&.call(OmniAI::Chat::Delta.new(text: part["text"]))
            end
          end

          merge_candidate!(candidate:, index:)
        end

        # @param candidate [Hash]
        # @param index [Integer]
        def merge_candidate!(candidate:, index:)
          if @data["candidates"][index].nil?
            @data["candidates"][index] = candidate
            return
          end

          existing = @data["candidates"][index]

          candidate.dig("content", "parts")&.each do |part|
            merge_part!(part:, candidate: existing)
          end

          # Preserve top-level candidate keys (most importantly `finishReason`) that arrive on a later — usually
          # terminal — chunk after the content has already streamed. Without this, the reason a generation stopped
          # (e.g. MAX_TOKENS / SAFETY) is silently dropped from the assembled response.
          candidate.each do |key, value|
            next if key.eql?("content")

            existing[key] = value
          end
        end

        # @param part [Hash]
        # @param candidate [Hash]
        def merge_part!(part:, candidate:)
          candidate["content"] ||= {}
          parts = candidate["content"]["parts"] ||= []
          last_part = parts.last

          if can_concatenate?(last_part, part)
            last_part["text"] += part["text"]
          else
            parts << part
          end
        end

        # True when `part` should concatenate into `last_part` rather than appear
        # as a new part. Two parts merge only when they're the same kind: both
        # text parts AND they agree on whether they're a reasoning (thought) chunk
        # or an answer chunk. Without the thought-state check, an answer chunk
        # arriving after thought chunks would coalesce into the trailing thought,
        # marking the visible answer as `thought: true` and causing callers to see
        # an empty `response.text`.
        #
        # @param last_part [Hash, nil]
        # @param part [Hash]
        # @return [Boolean]
        def can_concatenate?(last_part, part)
          return false if last_part.nil?
          return false unless last_part.key?("text") && part.key?("text")

          thought_part?(last_part) == thought_part?(part)
        end

        # Gemini may omit the "thought" key entirely on answer parts (so it's nil),
        # or set it explicitly to `false`, or `true` for thought parts. Normalize to
        # a single boolean so the comparison in can_concatenate? treats nil and false
        # as equivalent (both = "this is an answer part, not a thought part").
        #
        # @param part [Hash]
        # @return [Boolean]
        def thought_part?(part)
          part["thought"] == true
        end
      end
    end
  end
end

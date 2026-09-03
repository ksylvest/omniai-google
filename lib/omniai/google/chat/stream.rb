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

          validate!
          @data
        end

      protected

        # A stream that stopped early must not be handed back as an answer.
        #
        # Two ways it happens, both observed in production and both silent before this:
        #
        # 1. Google reports a failure that occurs AFTER the 200 by putting an `error` object in
        #    the stream. `process_data!` copies every non-candidate key into @data, so that
        #    error landed in @data["error"] and the caller received an empty, SUCCESSFUL
        #    response for an upstream outage. Reproduced: a 503 UNAVAILABLE arriving mid-stream
        #    yielded text="" with finish_reason=nil and no exception anywhere.
        #
        # 2. The stream closes cleanly with no terminal chunk, so no candidate ever reports a
        #    `finishReason`. Seen as thought-only responses -- every part `thought: true`, no
        #    answer text -- which read downstream as "the model returned nothing" rather than
        #    "the generation was cut off".
        #
        # This is not transport truncation; http.rb already raises on a truncated framed body.
        def validate!
          error = @data["error"]
          raise StreamError, "the stream carried an error: #{error_summary(error)}" if error

          candidates = @data["candidates"] || []
          return if candidates.any? && candidates.all? { |candidate| candidate["finishReason"] }

          raise IncompleteStreamError,
            "the stream ended without a finish reason: #{candidates_summary(candidates)}"
        end

        # @param error [Hash]
        # @return [String]
        def error_summary(error)
          "code=#{error['code'].inspect} status=#{error['status'].inspect} " \
            "message=#{error['message'].inspect}"
        end

        # STRUCTURE ONLY -- counts and flags, never part text. Consumers log these messages and
        # the text may be PHI.
        #
        # @param candidates [Array<Hash>]
        # @return [String]
        def candidates_summary(candidates)
          return "candidates=0" if candidates.empty?

          candidates.map.with_index do |candidate, index|
            parts = candidate.dig("content", "parts") || []
            "candidate=#{index} parts=#{parts.size} " \
              "thought_parts=#{parts.count { |part| part['thought'] }} " \
              "finish_reason=#{candidate['finishReason'].inspect}"
          end.join("; ")
        end

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

# frozen_string_literal: true

module OmniAI
  module Google
    class Live
      # Events yielded by a Live session, on its reader thread.
      module Event
        # Model speech: raw PCM16 (24 kHz, mono, little-endian) bytes.
        Audio = Data.define(:data, :mime_type) do
          def inspect = "#<#{self.class.name} bytes=#{data.bytesize} mime_type=#{mime_type}>"
        end

        # Model text (only when the session asks for text responses).
        Text = Data.define(:text)

        # A transcript fragment of the user's (`:user`) or the model's (`:model`) speech.
        Transcript = Data.define(:role, :text, :finished)

        # @!attribute calls [Array<FunctionCall>]
        ToolCall = Data.define(:calls)
        FunctionCall = Data.define(:id, :name, :arguments)
        ToolCallCancellation = Data.define(:ids)

        # The user spoke over the model; drop any audio still queued for playback.
        Interrupted = Data.define
        GenerationComplete = Data.define
        TurnComplete = Data.define

        # Speech start/end detected by the server; `offset` is seconds into the session's input audio.
        VoiceActivity = Data.define(:type, :offset)

        # The server will end the connection in `time_left` seconds.
        GoAway = Data.define(:time_left)
        ResumptionUpdate = Data.define(:handle, :resumable)

        # @!attribute usage [OmniAI::Chat::Usage] (`output_tokens` includes thinking)
        # @!attribute data [Hash] the raw usageMetadata, with per-modality token details
        Usage = Data.define(:usage, :data)

        # The session ended. `code` is nil when the connection dropped without a close frame; `error` is set when it
        # ended because of an exception (socket error, write timeout, or a raising handler). Google's close `reason`
        # can echo request content, so `inspect` leaves it out.
        Closed = Data.define(:code, :reason, :error) do
          def inspect = "#<#{self.class.name} code=#{code.inspect} error=#{error&.class.inspect}>"
        end
      end
    end
  end
end

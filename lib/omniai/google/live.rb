# frozen_string_literal: true

module OmniAI
  module Google
    # A Gemini Live API session on Vertex (BidiGenerateContent over a WebSocket): stream microphone audio in, receive
    # speech, transcripts and tool calls back.
    #
    # Usage:
    #
    #   session = client.live(model: "gemini-3.8-live", system: "...", tools: [RecordAnswer.new]) do |event|
    #     case event
    #     when OmniAI::Google::Live::Event::Audio then play(event.data)
    #     when OmniAI::Google::Live::Event::Closed then reconnect
    #     end
    #   end
    #   session.send_audio(pcm16_16khz)
    #   session.close
    #
    # Each session holds one socket and one reader thread. Events are yielded, and tools run, on that thread; the
    # `send_*` methods may be called from any thread. The gem never logs or raises audio, transcripts or tool arguments.
    class Live
      # @!attribute code [Integer, nil] the WebSocket close code
      # @!attribute reason [String, nil] Google's close reason; kept out of the message because it can echo content
      class Error < OmniAI::Error
        attr_reader :code, :reason

        def initialize(message, code: nil, reason: nil)
          super(message)
          @code = code
          @reason = reason
        end
      end

      class ClosedError < Error; end
      class TimeoutError < Error; end

      module Model
        GEMINI_3_8_LIVE = "gemini-3.8-live"
      end

      DEFAULT_MODEL = Model::GEMINI_3_8_LIVE
      INPUT_MIME_TYPE = "audio/pcm;rate=16000"
      PATH = "/ws/google.cloud.aiplatform.v1.LlmBidiService/BidiGenerateContent"
      SETUP_TIMEOUT = 15 # seconds
      WRITE_TIMEOUT = 5 # seconds
      BEHAVIORS = { blocking: "BLOCKING", non_blocking: "NON_BLOCKING" }.freeze
      ACTIVITY = { "ACTIVITY_START" => :start, "ACTIVITY_END" => :end }.freeze

      # Opens a session and waits for the server's setupComplete.
      #
      # @raise [Error] if the server rejects the setup or it times out
      #
      # @return [Live]
      def self.open(...)
        new(...).tap(&:open)
      end

      # @return [String, nil] the server's session id, once open
      attr_reader :session_id

      # @param client [OmniAI::Google::Client] must use Vertex credentials, a project and a location (e.g. "us")
      # @param model [String]
      # @param system [String, nil] the system instruction
      # @param tools [Array<OmniAI::Tool>, nil] run automatically; each result is sent back as a tool response
      # @param tool_behavior [Symbol, Hash] `:blocking` (default) or `:non_blocking`, or a Hash of tool name to either
      # @param voice [String, nil] a prebuilt voice name, e.g. "Kore"
      # @param transcription [Boolean] transcribe both the user's and the model's speech (default true)
      # @param vad [Hash, nil] automatic activity detection: `disabled:`, `start_sensitivity:` / `end_sensitivity:`
      #   (`:high` or `:low`), `prefix_padding_ms:`, `silence_ms:`
      # @param compression [Boolean, Hash] sliding-window context compression, which lifts the 15-minute session cap and
      #   bounds the context re-billed every turn. true uses Google's defaults (trigger at 80% of the context window);
      #   or pass `trigger_tokens:` / `target_tokens:`
      # @param resumption [Boolean, String, nil] true to receive resumption handles, or a handle to resume
      # @param write_timeout [Numeric] seconds a send may block before the session is closed
      #
      # @yieldparam event [Live::Event::*]
      def initialize(client:, model: DEFAULT_MODEL, system: nil, tools: nil, tool_behavior: :blocking, voice: nil,
        transcription: true, vad: nil, compression: false, resumption: nil, write_timeout: WRITE_TIMEOUT, &handler)
        @client = client
        @model = model
        @system = system
        @tools = tools || []
        @tool_behavior = tool_behavior
        @voice = voice
        @transcription = transcription
        @vad = vad
        @compression = compression
        @resumption = resumption
        @write_timeout = write_timeout
        @handler = handler
        @state = :new
      end

      # @raise [Error]
      #
      # @return [Live]
      def open
        raise ArgumentError, "#{self.class.name} requires Vertex credentials" unless @client.credentials?

        @ready = Queue.new
        @connection = Connection.new(
          url:,
          headers: { "Authorization" => @client.send(:auth) }, # a fresh token per connection
          write_timeout: @write_timeout,
          on_open: method(:on_open),
          on_message: method(:on_message),
          on_close: method(:on_close)
        )
        log("LIVE connect #{host} #{@model}")
        @connection.connect
        await_setup!
        self
      end

      # @return [Boolean]
      def open?
        @state == :open && @connection.open?
      end

      # @param audio [String] raw PCM16 audio, 16 kHz, mono, little-endian
      def send_audio(audio)
        deliver(realtimeInput: { audio: { mimeType: INPUT_MIME_TYPE, data: Base64.strict_encode64(audio) } })
      end

      # Tells the server the microphone paused, so it flushes any buffered audio.
      def end_audio
        deliver(realtimeInput: { audioStreamEnd: true })
      end

      # Sends a complete user turn of text, e.g. to re-seed context after reconnecting.
      #
      # @param text [String]
      def send_text(text)
        deliver(clientContent: { turns: [{ role: "user", parts: [{ text: }] }], turnComplete: true })
      end

      def close
        @connection&.close
      end

    private

      # @param message [Hash]
      #
      # @raise [ClosedError, TimeoutError]
      def deliver(message)
        raise ClosedError, "#{self.class.name} session is closed (session=#{@session_id})" unless open?

        @connection.send_text(JSON.generate(message))
      rescue Connection::WriteTimeout
        raise TimeoutError, "#{self.class.name} write timed out after #{@write_timeout}s (session=#{@session_id})"
      end

      def await_setup!
        result = @ready.pop(timeout: SETUP_TIMEOUT)
        return if result == :ready

        @connection.close
        raise Error, "#{self.class.name} setup timed out (model=#{@model})" if result.nil?

        code, reason, error = result
        raise Error.new("#{self.class.name} setup failed (model=#{@model} code=#{code.inspect} " \
          "error=#{error&.class.inspect})", code:, reason:)
      end

      def on_open
        @connection.send_text(JSON.generate(setup))
      end

      # @param data [String]
      def on_message(data)
        message = JSON.parse(data)
        if (complete = message["setupComplete"])
          @session_id = complete["sessionId"]
          @state = :open
          @ready << :ready
          return
        end

        events(message).each do |event|
          @handler&.call(event)
          respond(event) if event.is_a?(Event::ToolCall)
        end
      end

      def on_close(code, reason, error)
        state = @state
        @state = :closed
        log("LIVE close #{code || '-'} #{@session_id || '-'}")
        if state == :open
          @handler&.call(Event::Closed.new(code:, reason:, error:))
        else
          @ready << [code, reason, error]
        end
      end

      # Runs each called tool and sends the results. A raising tool answers with its error class only (never its
      # message, which may carry arguments), and the session carries on.
      #
      # @param event [Event::ToolCall]
      def respond(event)
        responses = event.calls.map do |call|
          tool = @tools.find { |candidate| candidate.name == call.name }
          response =
            if tool.nil?
              { error: "unknown tool: #{call.name}" }
            else
              begin
                { output: tool.call(call.arguments) }
              rescue StandardError => e
                { error: e.class.name }
              end
            end
          { id: call.id, name: call.name, response: }
        end
        deliver(toolResponse: { functionResponses: responses })
      end

      # Server message keys and their event builders, in the order events are yielded (usage after content).
      MESSAGE_EVENTS = {
        "serverContent" => :server_content_events,
        "toolCall" => :tool_call_events,
        "toolCallCancellation" => :cancellation_events,
        "voiceActivity" => :voice_activity_events,
        "sessionResumptionUpdate" => :resumption_events,
        "goAway" => :go_away_events,
        "usageMetadata" => :usage_events,
      }.freeze
      private_constant :MESSAGE_EVENTS

      # @param message [Hash]
      # @return [Array]
      def events(message)
        MESSAGE_EVENTS.flat_map { |key, builder| message[key] ? send(builder, message[key]) : [] }
      end

      def server_content_events(content)
        [
          *transcript_events(:user, content["inputTranscription"]),
          *model_turn_events(content["modelTurn"]),
          *transcript_events(:model, content["outputTranscription"]),
          (Event::Interrupted.new if content["interrupted"]),
          (Event::GenerationComplete.new if content["generationComplete"]),
          (Event::TurnComplete.new if content["turnComplete"]),
        ].compact
      end

      def transcript_events(role, transcription)
        return [] unless transcription

        [Event::Transcript.new(role:, text: transcription["text"], finished: transcription["finished"] == true)]
      end

      def model_turn_events(turn)
        (turn&.dig("parts") || []).filter_map do |part|
          if (inline = part["inlineData"])
            Event::Audio.new(data: Base64.decode64(inline["data"]), mime_type: inline["mimeType"])
          elsif part["text"] && !part["thought"]
            Event::Text.new(text: part["text"])
          end
        end
      end

      def tool_call_events(tool_call)
        calls = (tool_call["functionCalls"] || []).map do |call|
          Event::FunctionCall.new(id: call["id"], name: call["name"], arguments: call["args"] || {})
        end
        [Event::ToolCall.new(calls:)]
      end

      def cancellation_events(cancellation)
        [Event::ToolCallCancellation.new(ids: cancellation["ids"] || [])]
      end

      def voice_activity_events(activity)
        type = ACTIVITY.fetch(activity["type"], activity["type"])
        [Event::VoiceActivity.new(type:, offset: seconds(activity["audioOffset"]))]
      end

      def resumption_events(update)
        [Event::ResumptionUpdate.new(handle: update["newHandle"], resumable: update["resumable"] == true)]
      end

      def go_away_events(go_away)
        [Event::GoAway.new(time_left: seconds(go_away["timeLeft"]))]
      end

      def usage_events(usage)
        [Event::Usage.new(usage: Chat::UsageSerializer.deserialize(usage), data: usage)]
      end

      # @return [Hash]
      def setup
        {
          setup: {
            model: "projects/#{project_id}/locations/#{location_id}/publishers/google/models/#{@model}",
            generationConfig: { responseModalities: ["AUDIO"], speechConfig: speech_config }.compact,
            systemInstruction: ({ parts: [{ text: @system }] } if @system),
            tools: ([{ functionDeclarations: @tools.map { |tool| declaration(tool) } }] if @tools.any?),
            inputAudioTranscription: ({} if @transcription),
            outputAudioTranscription: ({} if @transcription),
            realtimeInputConfig: realtime_input_config,
            contextWindowCompression: context_window_compression,
            sessionResumption: session_resumption,
          }.compact,
        }
      end

      # @param tool [OmniAI::Tool]
      # @return [Hash]
      def declaration(tool)
        behavior = @tool_behavior.is_a?(Hash) ? @tool_behavior.fetch(tool.name, :blocking) : @tool_behavior
        Chat::ToolSerializer.serialize(tool).merge(behavior: BEHAVIORS.fetch(behavior.to_sym))
      end

      # @return [Hash, nil]
      def speech_config
        { voiceConfig: { prebuiltVoiceConfig: { voiceName: @voice } } } if @voice
      end

      # @return [Hash, nil]
      def realtime_input_config
        return unless @vad

        detection = {
          disabled: @vad[:disabled],
          startOfSpeechSensitivity: sensitivity("START", @vad[:start_sensitivity]),
          endOfSpeechSensitivity: sensitivity("END", @vad[:end_sensitivity]),
          prefixPaddingMs: @vad[:prefix_padding_ms],
          silenceDurationMs: @vad[:silence_ms],
        }.compact
        { automaticActivityDetection: detection }
      end

      # @return [String, nil] e.g. "START_SENSITIVITY_HIGH"
      def sensitivity(edge, level)
        "#{edge}_SENSITIVITY_#{level.to_s.upcase}" if level
      end

      # @return [Hash, nil]
      def context_window_compression
        return unless @compression

        options = @compression.is_a?(Hash) ? @compression : {}
        {
          triggerTokens: options[:trigger_tokens],
          slidingWindow: { targetTokens: options[:target_tokens] }.compact,
        }.compact
      end

      # @return [Hash, nil]
      def session_resumption
        case @resumption
        when true then {}
        when String then { handle: @resumption }
        end
      end

      # @param value [String, nil] e.g. "0.200s"
      # @return [Float, nil]
      def seconds(value)
        value&.delete_suffix("s")&.to_f
      end

      # @return [String] e.g. "wss://aiplatform.us.rep.googleapis.com/ws/..."
      def url
        "#{host.sub(/\Ahttp/, 'ws')}#{PATH}"
      end

      # @return [String]
      def host
        @client.instance_variable_get(:@host)
      end

      # @return [String]
      def project_id
        @client.instance_variable_get(:@project_id) || raise(ArgumentError, "project_id is required for Live")
      end

      # @return [String]
      def location_id
        @client.instance_variable_get(:@location_id) || raise(ArgumentError, "location_id is required for Live")
      end

      # @param message [String] ids, codes and classes only
      def log(message)
        @client.logger&.info(message)
      end
    end
  end
end

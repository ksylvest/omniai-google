# frozen_string_literal: true

module OmniAI
  module Google
    class Transcribe
      # Transcribes with a Gemini transcribe model (e.g. `gemini-3.5-transcribe`). Unlike Chirp (Cloud Speech-to-Text),
      # these are served by Vertex `generateContent` with the audio as the only part.
      #
      # Usage:
      #
      #   client.transcribe("interview.wav", model: "gemini-3.5-transcribe", diarization: true)
      class Gemini
        include TranscribeHelpers

        INLINE_LIMIT = 10_000_000 # bytes; larger audio goes through GCS

        # Leading bytes of the audio containers Gemini accepts. `generateContent` requires a mimeType.
        SIGNATURES = {
          "RIFF" => "audio/wav",
          "ID3" => "audio/mpeg",
          "\xFF\xFB".b => "audio/mpeg",
          "\xFF\xF3".b => "audio/mpeg",
          "\xFF\xF2".b => "audio/mpeg",
          "fLaC" => "audio/flac",
          "OggS" => "audio/ogg",
          "\x1A\x45\xDF\xA3".b => "audio/webm",
          "FORM" => "audio/aiff",
        }.freeze

        EXTENSIONS = {
          ".wav" => "audio/wav", ".mp3" => "audio/mpeg", ".flac" => "audio/flac", ".ogg" => "audio/ogg",
          ".opus" => "audio/ogg", ".webm" => "audio/webm", ".m4a" => "audio/mp4", ".mp4" => "audio/mp4",
          ".aac" => "audio/aac", ".aif" => "audio/aiff", ".aiff" => "audio/aiff",
        }.freeze

        # @param model [String]
        # @return [Boolean]
        def self.model?(model)
          String(model).start_with?("gemini-")
        end

        def self.process!(...)
          new(...).process!
        end

        # @param io [String, Pathname, IO] a file path, IO or `gs://` URI
        # @param client [OmniAI::Google::Client] must use Vertex credentials
        # @param model [String]
        # @param language [String, Array<String>, nil] optional - auto-detected when omitted
        # @param format [String, nil] optional - `verbose_json` adds per-utterance segments
        # @param diarization [Boolean] optional - speaker labels per segment (experimental)
        # @param word_timestamps [Boolean] optional - word times (experimental; can drop speech, see README)
        # @param vocabulary [Array<String>, nil] optional - custom vocabulary (up to 1,000 terms)
        def initialize(io, client:, model:, language: nil, format: nil, diarization: false, word_timestamps: false,
          vocabulary: nil)
          @io = io
          @client = client.for_model(model)
          @model = model
          @language = language
          @format = format || OmniAI::Transcribe::Format::JSON
          @diarization = diarization
          @word_timestamps = word_timestamps
          @vocabulary = vocabulary
        end

        # @raise [OmniAI::HTTPError, OmniAI::Error]
        #
        # @return [OmniAI::Transcribe::Transcription]
        def process!
          raise ArgumentError, "#{@model} requires Vertex credentials" unless @client.credentials?

          response = request!
          raise HTTPError, response unless response.status.ok?

          OmniAI::Transcribe::Transcription.parse(model: @model, format: @format, data: parse(response.parse))
        ensure
          cleanup_gcs_file(@uploaded_gcs_uri) if @uploaded_gcs_uri
          @uploaded_gcs_uri = nil
        end

      private

        # @return [HTTP::Response]
        def request!
          HTTP.persistent(host)
            .timeout(http_timeout_options)
            .accept(:json)
            .auth(@client.send(:auth))
            .post(path, json: payload)
        end

        # Served from the global endpoint and the us/eu multi-regions, never a single region, so a zonal Vertex
        # location_id maps to its multi-region (same rule as Chirp 3); `us` is the default.
        #
        # A location from `locations` is used as given.
        #
        # @return [String] "global", "us" or "eu", unless mapped
        def gemini_location_id
          return @client.instance_variable_get(:@location_id) if @client.located?

          case @client.instance_variable_get(:@location_id)
          when "global" then "global"
          when /\A(eu|europe)/i then "eu"
          else "us"
          end
        end

        # @return [String]
        def host
          Vertex.host(gemini_location_id)
        end

        # @return [String]
        def path
          "/v1/projects/#{project_id}/locations/#{gemini_location_id}/publishers/google/models/" \
            "#{@model}:generateContent"
        end

        # @return [Hash]
        def payload
          config = {
            languageCodes: language_codes,
            diarization: (true if @diarization),
            wordTimestamp: (true if @word_timestamps),
            customVocabulary: @vocabulary,
          }.compact

          payload = { contents: [{ role: "user", parts: [audio_part] }] }
          payload[:generationConfig] = { audioTranscriptionConfig: config } if config.any?
          payload
        end

        # @return [Hash]
        def audio_part
          return file_data(@io, EXTENSIONS.fetch(File.extname(@io).downcase, "audio/wav")) if gcs_uri?

          bytes = audio_bytes
          mime_type = sniff(bytes)
          return { inlineData: { mimeType: mime_type, data: Base64.strict_encode64(bytes) } } if inline?(bytes)

          @uploaded_gcs_uri = Bucket.process!(client: @client, io: StringIO.new(bytes))
          file_data(@uploaded_gcs_uri, mime_type)
        end

        # @param bytes [String]
        # @return [Boolean]
        def inline?(bytes)
          bytes.bytesize <= INLINE_LIMIT
        end

        # @return [Hash]
        def file_data(uri, mime_type)
          { fileData: { fileUri: uri, mimeType: mime_type } }
        end

        # @return [Boolean]
        def gcs_uri?
          @io.is_a?(String) && @io.start_with?("gs://")
        end

        # @return [String]
        def audio_bytes
          case @io
          when String, Pathname then File.binread(@io)
          when IO, StringIO
            @io.rewind if @io.respond_to?(:rewind)
            @io.read.b
          else raise ArgumentError, "unsupported input type: #{@io.class}"
          end
        end

        # @param bytes [String]
        # @return [String]
        def sniff(bytes)
          return "audio/mp4" if bytes.byteslice(4, 4) == "ftyp"

          SIGNATURES.each { |signature, mime_type| return mime_type if bytes.start_with?(signature.b) }
          raise ArgumentError, "unrecognised audio format (expected wav, mp3, flac, ogg, webm, m4a or aiff)"
        end

        # @param data [Hash]
        # @return [Hash]
        def parse(data)
          candidate = data.dig("candidates", 0) || {}
          parts = candidate.dig("content", "parts")
          if parts.nil? || parts.empty?
            raise OmniAI::Error, "#{@model} returned no content (finish reason #{candidate['finishReason']})"
          end

          segments = parts.map.with_index { |part, index| segment(part, index) }
          result = { "text" => segments.map { |segment| segment["text"] }.join(" ") }
          result["segments"] = segments if @format == OmniAI::Transcribe::Format::VERBOSE_JSON
          result
        end

        # @param part [Hash]
        # @param index [Integer]
        # @return [Hash]
        def segment(part, index)
          transcription = part["audioTranscription"] || {}
          words = transcription["words"]&.map do |word|
            { "word" => word["word"], "start" => parse_duration(word["startOffset"]),
              "end" => parse_duration(word["endOffset"]), }
          end

          {
            "id" => index,
            "text" => transcription["text"] || part["text"],
            "speaker" => transcription["speakerLabel"],
            "start" => words&.first&.fetch("start"),
            "end" => words&.last&.fetch("end"),
            "words" => words,
          }.compact
        end
      end
    end
  end
end

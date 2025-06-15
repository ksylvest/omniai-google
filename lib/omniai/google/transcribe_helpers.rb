# frozen_string_literal: true

module OmniAI
  module Google
    # Helper methods for transcription functionality
    module TranscribeHelpers # rubocop:disable Metrics/ModuleLength
    private

      # @return [String]
      def project_id
        @client.instance_variable_get(:@project_id) ||
          raise(ArgumentError, "project_id is required for transcription")
      end

      # @return [String]
      def location_id
        # Force global location for GCS uploads to ensure compatibility
        if needs_gcs_upload?
          "global"
        else
          @client.instance_variable_get(:@location_id) || "global"
        end
      end

      # @return [String]
      def speech_endpoint
        location_id == "global" ? "https://speech.googleapis.com" : "https://#{location_id}-speech.googleapis.com"
      end

      # @return [Array<String>, nil]
      def language_codes
        case @language
        when String
          [@language] unless @language.strip.empty?
        when Array
          cleaned = @language.compact.reject(&:empty?)
          cleaned if cleaned.any?
        when nil, ""
          nil # Auto-detect language when not specified
        else
          ["en-US"] # Default to English (multi-language only supported in global/us/eu locations)
        end
      end

      # @param input [String, Pathname, File, IO]
      # @return [String] Base64 encoded audio content
      def encode_audio(input)
        case input
        when String
          if File.exist?(input)
            Base64.strict_encode64(File.read(input))
          else
            input # Assume it's already base64 encoded
          end
        when Pathname, File, IO, StringIO
          Base64.strict_encode64(input.read)
        else
          raise ArgumentError, "Unsupported input type: #{input.class}"
        end
      end

      # @return [Boolean]
      def needs_gcs_upload?
        return false if @io.is_a?(String) && @io.start_with?("gs://")

        file_size = calculate_file_size
        # Force GCS upload for files > 10MB or if using long models for longer audio
        file_size > 10_000_000 || needs_long_form_recognition?
      end

      # @return [Boolean]
      def needs_long_form_recognition?
        # Use long-form models for potentially longer audio files
        return true if @model&.include?("long")

        # For large files, assume they might be longer than 60 seconds
        # Approximate: files larger than 1MB might be longer than 60 seconds
        calculate_file_size > 1_000_000
      end

      # @return [Integer]
      def calculate_file_size
        case @io
        when String
          File.exist?(@io) ? File.size(@io) : 0
        when File, IO, StringIO
          @io.respond_to?(:size) ? @io.size : 0
        else
          0
        end
      end

      # @return [Hash]
      def build_config
        config = {
          model: @model,
          autoDecodingConfig: {},
        }

        # Only include languageCodes if specified and non-empty (omit for auto-detection)
        lang_codes = language_codes
        config[:languageCodes] = if lang_codes&.any?
                                   lang_codes
                                 else
                                   # Google API requires languageCodes field - use multiple languages for auto-detection
                                   %w[en-US es-US]
                                 end

        features = build_features
        config[:features] = features unless features.empty?

        if OmniAI::Google.config.respond_to?(:transcribe_options)
          config.merge!(OmniAI::Google.config.transcribe_options)
        end

        config
      end

      # @return [Hash]
      def build_features
        case @format
        when OmniAI::Transcribe::Format::VERBOSE_JSON
          { enableAutomaticPunctuation: true, enableWordTimeOffsets: true, enableWordConfidence: true }
        when OmniAI::Transcribe::Format::JSON
          { enableAutomaticPunctuation: true }
        else
          {}
        end

        # NOTE: Speaker diarization is not directly supported in Speech-to-Text v2 API
        # Multi-language detection works automatically when languageCodes is omitted
      end

      # @param payload_data [Hash]
      def add_audio_data(payload_data)
        if @io.is_a?(String) && @io.start_with?("gs://")
          payload_data[:uri] = @io
        elsif needs_gcs_upload?
          gcs_uri = Bucket.process!(client: @client, io: @io)
          payload_data[:uri] = gcs_uri
        else
          payload_data[:content] = encode_audio(@io)
        end
      end

      # @return [Hash] Payload for batch recognition
      def batch_payload
        config = build_config

        # Get audio URI for batch processing
        audio_uri = if @io.is_a?(String) && @io.start_with?("gs://")
                      @io
                    else
                      # Force GCS upload for batch recognition
                      Bucket.process!(client: @client, io: @io)
                    end

        {
          config:,
          files: [{ uri: audio_uri }],
          recognitionOutputConfig: {
            inlineResponseConfig: {},
          },
        }
      end

      # @param operation_name [String]
      # @raise [HTTPError]
      #
      # @return [Hash]
      def poll_operation!(operation_name)
        endpoint = speech_endpoint
        connection = HTTP.persistent(endpoint)
          .timeout(connect: @client.timeout, write: @client.timeout, read: @client.timeout)
          .accept(:json)

        # Add authentication if using credentials
        connection = connection.auth("Bearer #{@client.send(:auth).split.last}") if @client.credentials?

        max_attempts = 60 # Maximum 15 minutes (15 second intervals)
        attempt = 0

        loop do
          attempt += 1

          raise HTTPError, "Operation timed out after #{max_attempts * 15} seconds" if attempt > max_attempts

          operation_response = connection.get("/v2/#{operation_name}", params: operation_params)

          raise HTTPError, operation_response unless operation_response.status.ok?

          operation_data = operation_response.parse

          # Check for errors
          if operation_data["error"]
            error_message = operation_data.dig("error", "message") || "Unknown error"
            raise HTTPError, "Operation failed: #{error_message}"
          end

          # Check if done
          return operation_data if operation_data["done"]

          # Wait before polling again
          sleep(15)
        end
      end

      # @return [HTTP::Response]
      def request_batch!
        endpoint = speech_endpoint
        connection = HTTP.persistent(endpoint)
          .timeout(connect: @client.timeout, write: @client.timeout, read: @client.timeout)
          .accept(:json)

        # Add authentication if using credentials
        connection = connection.auth("Bearer #{@client.send(:auth).split.last}") if @client.credentials?

        connection.post(batch_path, params: operation_params, json: batch_payload)
      end

      # @return [String]
      def batch_path
        # Use batchRecognize endpoint for async recognition
        recognizer_path = "projects/#{project_id}/locations/#{location_id}/recognizers/#{recognizer_name}"
        "/v2/#{recognizer_path}:batchRecognize"
      end

      # @return [Hash]
      def operation_params
        { key: (@client.api_key unless @client.credentials?) }.compact
      end

      # @return [String]
      def recognizer_name
        # Always use the default recognizer - the model is specified in the config
        "_"
      end

      # @param result [Hash] Operation result from batch recognition
      # @return [Hash] Extracted transcript with timing info or String for simple text
      def extract_batch_transcript(result)
        batch_results = result.dig("response", "results")
        return "" unless batch_results

        # Get the first (and likely only) file result
        file_result = batch_results.values.first
        return "" unless file_result&.dig("transcript", "results")

        transcript_segments = file_result["transcript"]["results"]

        # For VERBOSE_JSON format, return detailed timing information
        if @format == OmniAI::Transcribe::Format::VERBOSE_JSON
          extract_detailed_transcript(transcript_segments, file_result)
        else
          # For simple formats, just concatenate text
          segments = transcript_segments.map do |segment|
            segment.dig("alternatives", 0, "transcript")
          end.compact
          segments.join(" ")
        end
      end

      # @param segments [Array] Transcript segments from Google API
      # @param file_result [Hash] Full file result with metadata
      # @return [Hash] Detailed transcript with timing and metadata
      def extract_detailed_transcript(segments, file_result)
        total_duration = file_result.dig("metadata", "totalBilledDuration")

        detailed_segments = segments.map.with_index do |segment, index|
          alternative = segment.dig("alternatives", 0)
          next unless alternative

          {
            segment_id: index,
            text: alternative["transcript"],
            confidence: alternative["confidence"],
            language_code: segment["languageCode"],
            end_time: segment["resultEndOffset"],
            words: extract_word_timings(alternative),
          }
        end.compact

        {
          text: detailed_segments.map { |s| s[:text] }.join(" "),
          total_duration:,
          segments: detailed_segments,
        }
      end

      # @param alternative [Hash] Alternative with word-level timings
      # @return [Array] Word-level timing information
      def extract_word_timings(alternative)
        return [] unless alternative["words"]

        alternative["words"].map do |word_info|
          {
            word: word_info["word"],
            start_time: word_info["startOffset"],
            end_time: word_info["endOffset"],
            confidence: word_info["confidence"],
          }
        end
      end

      # @param gcs_uri [String] GCS URI to delete (e.g., "gs://bucket/file.mp3")
      def cleanup_gcs_file(gcs_uri)
        return unless valid_gcs_uri?(gcs_uri)

        bucket_name, object_name = parse_gcs_uri(gcs_uri)
        return unless bucket_name && object_name

        delete_gcs_object(bucket_name, object_name, gcs_uri)
      end

      # @param gcs_uri [String]
      # @return [Boolean]
      def valid_gcs_uri?(gcs_uri)
        gcs_uri&.start_with?("gs://")
      end

      # @param gcs_uri [String]
      # @return [Array<String>] [bucket_name, object_name]
      def parse_gcs_uri(gcs_uri)
        uri_parts = gcs_uri.sub("gs://", "").split("/", 2)
        [uri_parts[0], uri_parts[1]]
      end

      # @param bucket_name [String]
      # @param object_name [String]
      # @param gcs_uri [String]
      def delete_gcs_object(bucket_name, object_name, gcs_uri)
        storage = create_storage_client
        bucket = storage.bucket(bucket_name)
        return unless bucket

        file = bucket.file(object_name)
        file&.delete
      rescue ::Google::Cloud::Error => e
        @client.logger&.warn("Failed to cleanup GCS file #{gcs_uri}: #{e.message}")
      end

      # @return [Google::Cloud::Storage]
      def create_storage_client
        credentials = @client.instance_variable_get(:@credentials)
        ::Google::Cloud::Storage.new(project_id:, credentials:)
      end
    end
  end
end

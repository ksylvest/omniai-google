# frozen_string_literal: true

module OmniAI
  module Google
    # A Google transcribe implementation.
    #
    # Usage:
    #
    #   transcribe = OmniAI::Google::Transcribe.new(client: client)
    #   transcribe.process!(audio_file)
    class Transcribe < OmniAI::Transcribe
      include TranscribeHelpers
      module Model
        CHIRP_2 = "chirp_2"
        CHIRP = "chirp"
        LATEST_LONG = "latest_long"
        LATEST_SHORT = "latest_short"
        TELEPHONY_LONG = "telephony_long"
        TELEPHONY_SHORT = "telephony_short"
        MEDICAL_CONVERSATION = "medical_conversation"
        MEDICAL_DICTATION = "medical_dictation"
      end

      DEFAULT_MODEL = Model::LATEST_SHORT
      DEFAULT_RECOGNIZER = "_"

      # @raise [HTTPError]
      #
      # @return [OmniAI::Transcribe::Transcription]
      def process!
        if needs_async_recognition?
          process_async!
        else
          process_sync!
        end
      end

    private

      # @return [Boolean]
      def needs_async_recognition?
        # Use async for long-form models or when GCS is needed
        needs_long_form_recognition? || needs_gcs_upload?
      end

      # @raise [HTTPError]
      #
      # @return [OmniAI::Transcribe::Transcription]
      def process_sync!
        response = request!
        handle_sync_response_errors(response)

        data = response.parse
        transcript = data.dig("results", 0, "alternatives", 0, "transcript") || ""

        transformed_data = build_sync_response_data(data, transcript)
        Transcription.parse(model: @model, format: @format, data: transformed_data)
      end

      # @raise [HTTPError]
      #
      # @return [OmniAI::Transcribe::Transcription]
      def process_async!
        # Track if we uploaded the file for cleanup
        uploaded_gcs_uri = nil

        # Start the batch recognition job
        response = request_batch!

        raise HTTPError, response unless response.status.ok?

        operation_data = response.parse
        operation_name = operation_data["name"]

        raise HTTPError, "No operation name returned from batch recognition request" unless operation_name

        # Extract GCS URI for cleanup if we uploaded it
        if operation_data.dig("metadata", "batchRecognizeRequest", "files")
          file_uri = operation_data.dig("metadata", "batchRecognizeRequest", "files", 0, "uri")
          # Only mark for cleanup if it's not a user-provided GCS URI
          uploaded_gcs_uri = file_uri unless @io.is_a?(String) && @io.start_with?("gs://")
        end

        # Poll for completion
        result = poll_operation!(operation_name)

        # Extract transcript from completed operation
        transcript_data = extract_batch_transcript(result)

        # Clean up uploaded file if we created it
        cleanup_gcs_file(uploaded_gcs_uri) if uploaded_gcs_uri

        Transcription.parse(model: @model, format: @format, data: transcript_data)
      end

    protected

      # @return [String]
      def project_id
        @client.project_id || raise(ArgumentError, "project_id is required for transcription")
      end

      # @return [String]
      def location_id
        case @model
        when "chirp_2" then "us-central1"
        else @client.location_id || "global"
        end
      end

      # @return [String]
      def endpoint
        location_id == "global" ? "https://speech.googleapis.com" : "https://#{location_id}-speech.googleapis.com"
      end

      def connection
        @connection ||= begin
          connection = HTTP.persistent(endpoint)
            .timeout(connect: @client.timeout, write: @client.timeout, read: @client.timeout)
            .accept(:json)
          connection = connection.auth(@client.auth) if @client.credentials?
          connection
        end
      end

      # @return [HTTP::Response]
      def request!
        connection.accept(:json).post(path, params:, json: payload)
      end

      # @return [Hash]
      def payload
        config = build_config
        payload_data = { config: }
        add_audio_data(payload_data)
        payload_data
      end

      # @return [String]
      def path
        "/v2/projects/#{project_id}/locations/#{location_id}/recognizers/_:recognize"
      end

      # @return [Hash]
      def params
        { key: (@client.api_key unless @client.credentials?) }.compact
      end
    end
  end
end

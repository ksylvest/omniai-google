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
        CHIRP_3 = "chirp_3"
        CHIRP_2 = "chirp_2"
        CHIRP = "chirp"
        LATEST_LONG = "latest_long"
        LATEST_SHORT = "latest_short"
        TELEPHONY = "telephony"
        TELEPHONY_LONG = "telephony_long"
        TELEPHONY_SHORT = "telephony_short"
        MEDICAL_CONVERSATION = "medical_conversation"
        MEDICAL_DICTATION = "medical_dictation"
      end

      DEFAULT_MODEL = Model::LATEST_SHORT
      DEFAULT_RECOGNIZER = "_"

      # @return [Context]
      CONTEXT = Context.build do |context|
        # No custom deserializers needed - let base class handle parsing
      end

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
        # Start the batch recognition job
        response = request_batch!

        raise HTTPError, response unless response.status.ok?

        operation_data = response.parse
        operation_name = operation_data["name"]

        raise HTTPError, "No operation name returned from batch recognition request" unless operation_name

        # Poll for completion
        result = poll_operation!(operation_name)

        # Extract transcript from completed operation
        transcript_data = extract_batch_transcript(result)

        Transcription.parse(model: @model, format: @format, data: transcript_data)
      ensure
        # Delete our upload even when the request fails or polling times out
        cleanup_gcs_file(@uploaded_gcs_uri) if @uploaded_gcs_uri
        @uploaded_gcs_uri = nil
      end

    protected

      # @return [Context]
      def context
        CONTEXT
      end

      # @return [HTTP::Response]
      def request!
        # Speech-to-Text API uses different endpoints for regional vs global
        endpoint = speech_endpoint
        speech_connection = HTTP.persistent(endpoint)
          .timeout(http_timeout_options)
          .accept(:json)

        # Add authentication if using credentials
        speech_connection = speech_connection.auth("Bearer #{@client.send(:auth).split.last}") if @client.credentials?

        speech_connection.post(path, params:, json: payload)
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
        # Always use Speech-to-Text API v2 with recognizers
        recognizer_path = "projects/#{project_id}/locations/#{location_id}/recognizers/#{recognizer_name}"
        "/v2/#{recognizer_path}:recognize"
      end

      # @return [Hash]
      def params
        { key: (@client.api_key unless @client.credentials?) }.compact
      end
    end
  end
end

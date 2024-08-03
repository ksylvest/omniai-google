# frozen_string_literal: true

module OmniAI
  module Google
    # Configuration for Google.
    class Config < OmniAI::Config
      DEFAULT_HOST = 'https://generativelanguage.googleapis.com'
      DEFAULT_VERSION = 'v1'
      DEFAULT_LOCATION = 'us-central1'

      # @!attribute [rw] version
      #   @return [String, nil]
      attr_accessor :version

      # @!attribute [rw] project_id
      #   @return [String, nil]
      attr_accessor :project_id

      # @!attribute [rw] location
      #   @return [String, nil]
      attr_accessor :location

      # @param api_key [String, nil] optional - defaults to `ENV['GOOGLE_API_KEY']`
      # @param host [String, nil] optional - defaults to `ENV['GOOGLE_HOST'] w/ fallback to `DEFAULT_HOST`
      # @param version [String, nil] optional - defaults to `ENV['GOOGLE_VERSION'] w/ fallback to `DEFAULT_VERSION`
      # @param logger [Logger, nil] optional - defaults to
      # @param timeout [Integer, Hash, nil] optional
      def initialize(
        api_key: ENV.fetch('GOOGLE_API_KEY', nil),
        project_id: ENV.fetch('GOOGLE_PROJECT_ID', nil),
        version: ENV.fetch('GOOGLE_VERSION', DEFAULT_VERSION),
        location: ENV.fetch('GOOGLE_LOCATION', DEFAULT_LOCATION),
        logger: nil,
        timeout: nil
      )
        host = project_id ? "https://#{location}-aiplatform.googleapis.com" : DEFAULT_HOST

        super(api_key:, host:, logger:, timeout:)
        @project_id = project_id
        @location = location
        @version = version
      end
    end
  end
end

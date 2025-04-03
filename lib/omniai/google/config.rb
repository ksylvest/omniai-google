# frozen_string_literal: true

module OmniAI
  module Google
    # Configuration for Google.
    class Config < OmniAI::Config
      module Version
        STABLE = "v1"
        BETA = "v1beta"
      end

      DEFAULT_HOST = "https://generativelanguage.googleapis.com"

      # @!attribute [rw] credentials
      #   @return [String, nil]
      attr_accessor :credentials

      # @param api_key [String, nil] optional - defaults to `ENV['GOOGLE_API_KEY']`
      # @param credentials [Google::Auth::ServiceAccountCredentials, nil] optional
      # @param host [String, nil] optional - defaults to `ENV['GOOGLE_HOST'] w/ fallback to `DEFAULT_HOST`
      # @param version [String, nil] optional - defaults to `ENV['GOOGLE_VERSION'] w/ fallback to `DEFAULT_VERSION`
      # @param logger [Logger, nil] optional
      # @param timeout [Integer, Hash, nil] optional
      def initialize(
        api_key: ENV.fetch("GOOGLE_API_KEY", nil),
        credentials: nil,
        host: ENV.fetch("GOOGLE_HOST", DEFAULT_HOST),
        version: ENV.fetch("GOOGLE_VERSION", DEFAULT_VERSION),
        logger: nil,
        timeout: nil
      )
        super(api_key:, host:, logger:, timeout:)
        @credentials = credentials

      # @return [String]
      def version
        @host.eql?(DEFAULT_HOST) ? Version::BETA : Version::STABLE
      end
      end
    end
  end
end

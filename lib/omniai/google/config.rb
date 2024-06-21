# frozen_string_literal: true

module OmniAI
  module Google
    # Configuration for Google.
    class Config < OmniAI::Config
      DEFAULT_HOST = 'https://generativelanguage.googleapis.com'
      DEFAULT_VERSION = 'v1'

      # @!attribute [rw] version
      #   @return [String, nil]
      attr_accessor :version

      # @param api_key [String, nil] optional - defaults to `ENV['GOOGLE_API_KEY']`
      # @param host [String, nil] optional - defaults to `ENV['GOOGLE_HOST'] w/ fallback to `DEFAULT_HOST`
      # @param version [String, nil] optional - defaults to `ENV['GOOGLE_VERSION'] w/ fallback to `DEFAULT_VERSION`
      # @param logger [Logger, nil] optional - defaults to
      # @param timeout [Integer, Hash, nil] optional
      def initialize(
        api_key: ENV.fetch('GOOGLE_API_KEY', nil),
        host: ENV.fetch('GOOGLE_HOST', DEFAULT_HOST),
        version: ENV.fetch('GOOGLE_VERSION', DEFAULT_VERSION),
        logger: nil,
        timeout: nil
      )
        super(api_key:, host:, logger:, timeout:)
        @version = version
      end
    end
  end
end

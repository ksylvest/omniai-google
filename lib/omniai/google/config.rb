# frozen_string_literal: true

module OmniAI
  module Google
    # Config for the Google `api_key` / `host` / `logger` / `version`, `chat_options`.
    class Config < OmniAI::Config
      attr_accessor :chat_options, :version

      def initialize
        super
        @api_key = ENV.fetch('GOOGLE_API_KEY', nil)
        @host = ENV.fetch('GOOGLE_HOST', 'https://generativelanguage.googleapis.com')
        @version = ENV.fetch('GOOGLE_VERSION', 'v1')
        @chat_options = {}
      end
    end
  end
end

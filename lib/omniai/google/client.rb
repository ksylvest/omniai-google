# frozen_string_literal: true

module OmniAI
  module Google
    # A Google client implementation. Usage:
    #
    # w/ `api_key``:
    #   client = OmniAI::Google::Client.new(api_key: '...')
    #
    # w/ ENV['GOOGLE_API_KEY']:
    #
    #   ENV['GOOGLE_API_KEY'] = '...'
    #   client = OmniAI::Google::Client.new
    #
    # w/ config:
    #
    #   OmniAI::Google.configure do |config|
    #     config.api_key = '...'
    #   end
    #
    #   client = OmniAI::Google::Client.new
    class Client < OmniAI::Client
      # @!attribute [rw] version
      #   @return [String, nil]
      attr_accessor :version

      # @param api_key [String] optional - defaults to `OmniAI::Google.config.api_key`
      # @param host [String] optional - defaults to `OmniAI::Google.config.host`
      # @param version [String] optional - defaults to `OmniAI::Google.config.version`
      # @param logger [Logger] optional - defaults to `OmniAI::Google.config.logger`
      # @param timeout [Integer] optional - defaults to `OmniAI::Google.config.timeout`
      def initialize(
        api_key: OmniAI::Google.config.api_key,
        logger: OmniAI::Google.config.logger,
        host: OmniAI::Google.config.host,
        version: OmniAI::Google.config.version,
        timeout: OmniAI::Google.config.timeout
      )
        raise(ArgumentError, %(ENV['GOOGLE_API_KEY'] must be defined or `api_key` must be passed)) if api_key.nil?

        super(api_key:, host:, logger:, timeout:)

        @version = version
      end

      # @raise [OmniAI::Error]
      #
      # @param messages [String] optional
      # @param model [String] optional
      # @param format [Symbol] optional :text or :json
      # @param temperature [Float, nil] optional
      # @param stream [Proc, nil] optional
      # @param tools [Array<OmniAI::Chat::Tool>, nil] optional
      #
      # @yield [prompt] optional
      # @yieldparam prompt [OmniAI::Chat::Prompt]
      #
      # @return [OmniAI::Chat::Completion]
      def chat(messages = nil, model: Chat::DEFAULT_MODEL, temperature: nil, format: nil, stream: nil, tools: nil, &)
        Chat.process!(messages, model:, temperature:, format:, stream:, tools:, client: self, &)
      end
    end
  end
end

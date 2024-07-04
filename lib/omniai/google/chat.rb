# frozen_string_literal: true

module OmniAI
  module Google
    # A Google chat implementation.
    #
    # Usage:
    #
    #   chat = OmniAI::Google::Chat.new(client: client)
    #   chat.completion('Tell me a joke.')
    #   chat.completion(['Tell me a joke.'])
    #   chat.completion({ role: 'user', content: 'Tell me a joke.' })
    #   chat.completion([{ role: 'system', content: 'Tell me a joke.' }])
    class Chat < OmniAI::Chat
      module Model
        GEMINI_1_0_PRO = 'gemini-1.0-pro'
        GEMINI_1_5_PRO = 'gemini-1.5-pro'
        GEMINI_1_5_FLASH = 'gemini-1.5-flash'
        GEMINI_1_0_PRO_LATEST = 'gemini-1.0-pro-latest'
        GEMINI_1_5_PRO_LATEST = 'gemini-1.5-pro-latest'
        GEMINI_1_5_FLASH_LATEST = 'gemini-1.5-flash-latest'
        GEMINI_PRO = GEMINI_1_5_PRO
        GEMINI_FLASH = GEMINI_1_5_FLASH
      end

      protected

      # @return [HTTP::Response]
      def request!
        @client
          .connection
          .accept(:json)
          .post(path, params: {
            key: @client.api_key,
            alt: ('sse' if @stream),
          }.compact, json: payload)
      end

      # @return [Hash]
      def payload
        OmniAI::Google.config.chat_options.merge({
          contents:,
          generationConfig: generation_config,
        }).compact
      end

      # @return [Hash]
      def generation_config
        return unless @temperature

        { temperature: @temperature }.compact
      end

      # Example:
      #
      #   [{ role: 'user', parts: [{ text: '...' }] }]
      #
      # @return [Array<Hash>]
      def contents
        messages.map do |message|
          { role: message[:role], parts: [{ text: message[:content] }] }
        end
      end

      # @return [String]
      def path
        "/#{@client.version}/models/#{@model}:#{operation}"
      end

      # @return [String]
      def operation
        @stream ? 'streamGenerateContent' : 'generateContent'
      end
    end
  end
end

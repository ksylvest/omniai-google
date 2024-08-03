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

      DEFAULT_MODEL = Model::GEMINI_PRO

      TEXT_SERIALIZER = lambda do |content, *|
        { text: content.text }
      end

      # @param [Message]
      # @return [Hash]
      # @example
      #   message = Message.new(...)
      #   MESSAGE_SERIALIZER.call(message)
      MESSAGE_SERIALIZER = lambda do |message, context:|
        parts = message.content.is_a?(String) ? [Text.new(message.content)] : message.content
        role = message.system? ? Role::USER : message.role

        {
          role:,
          parts: parts.map { |part| part.serialize(context:) },
        }
      end

      # @param [Media]
      # @return [Hash]
      # @example
      #   media = Media.new(...)
      #   MEDIA_SERIALIZER.call(media)
      MEDIA_SERIALIZER = lambda do |media, *|
        {
          inlineData: {
            mimeType: media.type,
            data: media.data,
          },
        }
      end

      # @return [Context]
      CONTEXT = Context.build do |context|
        context.serializers[:message] = MESSAGE_SERIALIZER
        context.serializers[:text] = TEXT_SERIALIZER
        context.serializers[:file] = MEDIA_SERIALIZER
        context.serializers[:url] = MEDIA_SERIALIZER
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
          tools:,
          generationConfig: generation_config,
        }).compact
      end

      # @return [Hash]
      def tools
        return unless @tools

        [
          function_declarations: @tools&.map(&:prepare),
        ]
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
        @prompt.serialize(context: CONTEXT)
      end

      # @return [String]
      def path
        "#{@client.path}/models/#{@model}:#{operation}"
      end

      # @return [String]
      def operation
        @stream ? 'streamGenerateContent' : 'generateContent'
      end
    end
  end
end

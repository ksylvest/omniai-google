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
        GEMINI_1_0_PRO = "gemini-1.0-pro"
        GEMINI_1_5_PRO = "gemini-1.5-pro"
        GEMINI_1_5_FLASH = "gemini-1.5-flash"
        GEMINI_1_0_PRO_LATEST = "gemini-1.0-pro-latest"
        GEMINI_1_5_PRO_LATEST = "gemini-1.5-pro-latest"
        GEMINI_1_5_FLASH_LATEST = "gemini-1.5-flash-latest"
        GEMINI_PRO = GEMINI_1_5_PRO
        GEMINI_FLASH = GEMINI_1_5_FLASH
      end

      DEFAULT_MODEL = Model::GEMINI_PRO

      JSON_MIME_TYPE = "application/json"

      # @return [Context]
      CONTEXT = Context.build do |context|
        context.serializers[:text] = TextSerializer.method(:serialize)
        context.deserializers[:text] = TextSerializer.method(:deserialize)

        context.serializers[:file] = MediaSerializer.method(:serialize)
        context.serializers[:url] = MediaSerializer.method(:serialize)

        context.serializers[:tool_call] = ToolCallSerializer.method(:serialize)
        context.deserializers[:tool_call] = ToolCallSerializer.method(:deserialize)

        context.serializers[:tool_call_result] = ToolCallResultSerializer.method(:serialize)
        context.deserializers[:tool_call_result] = ToolCallResultSerializer.method(:deserialize)

        context.serializers[:function] = FunctionSerializer.method(:serialize)
        context.deserializers[:function] = FunctionSerializer.method(:deserialize)

        context.serializers[:usage] = UsageSerializer.method(:serialize)
        context.deserializers[:usage] = UsageSerializer.method(:deserialize)

        context.serializers[:payload] = PayloadSerializer.method(:serialize)
        context.deserializers[:payload] = PayloadSerializer.method(:deserialize)

        context.serializers[:choice] = ChoiceSerializer.method(:serialize)
        context.deserializers[:choice] = ChoiceSerializer.method(:deserialize)

        context.serializers[:message] = MessageSerializer.method(:serialize)
        context.deserializers[:message] = MessageSerializer.method(:deserialize)

        context.deserializers[:content] = ContentSerializer.method(:deserialize)

        context.serializers[:tool] = ToolSerializer.method(:serialize)
      end

    protected

      # @return [Context]
      def context
        CONTEXT
      end

      # @return [HTTP::Response]
      def request!
        @client
          .connection
          .accept(:json)
          .post(path, params: {
            key: @client.api_key,
            alt: ("sse" if @stream),
          }.compact, json: payload)
      end

      # @return [Hash]
      def payload
        OmniAI::Google.config.chat_options.merge({
          system_instruction: @prompt.messages.find(&:system?)&.serialize(context:),
          contents: @prompt.messages.reject(&:system?).map { |message| message.serialize(context:) },
          tools:,
          generationConfig: generation_config,
        }).compact
      end

      # @return [Hash]
      def tools
        return unless @tools&.any?

        [
          function_declarations: @tools.map { |tool| tool.serialize(context:) },
        ]
      end

      # @return [Hash]
      def generation_config
        response_mime_type = (JSON_MIME_TYPE if json_mime_type?)

        return unless @temperature || response_mime_type

        {
          temperature: @temperature,
          responseMimeType: response_mime_type,
        }.compact
      end

      # Checks if setting a jsonMimeType is supported
      # @return [Boolean]
      def json_mime_type?
        @client.version == OmniAI::Google::Config::Version::BETA && @format.eql?(:json)
      end

      # @return [String]
      def path
        "/#{@client.version}/models/#{@model}:#{operation}"
      end

      # @return [String]
      def operation
        @stream ? "streamGenerateContent" : "generateContent"
      end

      # @return [Array<Message>]
      def build_tool_call_messages(tool_call_list)
        content = tool_call_list.map do |tool_call|
          ToolCallResult.new(tool_call_id: tool_call.id, content: execute_tool_call(tool_call))
        end

        [Message.new(role: "function", content:)]
      end
    end
  end
end

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
        GEMINI_2_5_PRO = "gemini-2.5-pro"
        GEMINI_3_0_PRO = "gemini-3-pro-preview"
        GEMINI_3_1_PRO = "gemini-3.1-pro-preview"
        GEMINI_1_5_FLASH = "gemini-1.5-flash"
        GEMINI_2_0_FLASH = "gemini-2.0-flash"
        GEMINI_2_5_FLASH = "gemini-2.5-flash"
        GEMINI_3_FLASH = "gemini-3-flash-preview"
        GEMINI_3_5_FLASH = "gemini-3.5-flash"
        GEMINI_3_6_FLASH = "gemini-3.6-flash"
        GEMINI_3_7_FLASH = "gemini-3.7-flash"
        GEMINI_3_8_FLASH = "gemini-3.8-flash"
        GEMINI_4_ARGON = "gemini-4-argon"
        GEMINI_4_CARBON = "gemini-4-carbon"
        GEMINI_4_HYDROGEN = "gemini-4-hydrogen"
        GEMINI_4_NEON = "gemini-4-neon"
        GEMINI_PRO = GEMINI_3_1_PRO
        GEMINI_FLASH = GEMINI_3_8_FLASH
      end

      DEFAULT_MODEL = Model::GEMINI_FLASH

      module ResponseMimeType
        JSON = "application/json"
        TEXT = "text/plain"
        SCHEMA = JSON
      end

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

        context.serializers[:response] = ResponseSerializer.method(:serialize)
        context.deserializers[:response] = ResponseSerializer.method(:deserialize)

        context.serializers[:choice] = ChoiceSerializer.method(:serialize)
        context.deserializers[:choice] = ChoiceSerializer.method(:deserialize)

        context.serializers[:message] = MessageSerializer.method(:serialize)
        context.deserializers[:message] = MessageSerializer.method(:deserialize)

        context.deserializers[:content] = ContentSerializer.method(:deserialize)

        context.serializers[:tool] = ToolSerializer.method(:serialize)

        context.serializers[:thinking] = ThinkingSerializer.method(:serialize)
        context.deserializers[:thinking] = ThinkingSerializer.method(:deserialize)
      end

      # Google rejects these on a request that uses `cachedContent`; they must live in the cache.
      CACHE_EXCLUDED_KEYS = %i[system_instruction systemInstruction tools tool_config toolConfig].freeze

      # A cached request that gets one of these, or a 404, is retried once uncached (`cache:` only).
      CACHE_GONE_STATUSES = %w[NOT_FOUND FAILED_PRECONDITION].freeze

      # Vertex answers a request against a deleted cache with 400 INVALID_ARGUMENT, the same status as a bad prompt,
      # so this one is retried only when a `get` of the cache then returns 404.
      CACHE_CHECK_STATUS = "INVALID_ARGUMENT"

      # @param tools [Array<OmniAI::Tool, Symbol, String>, nil]
      #
      # @return [Array<Hash>, nil]
      def self.serialize_tools(tools)
        return if tools.nil? || tools.empty?

        [
          { function_declarations: tools.grep(OmniAI::Tool).map { |tool| tool.serialize(context: CONTEXT) } },
        ].concat(tools.filter { |tool| tool.is_a?(Symbol) || tool.is_a?(String) }.map { |name| { name => {} } })
      end

      # `client` is swapped for `client.for_model(model)`, so `locations` routes the request.
      #
      # Caching (Gemini explicit context caching, off by default):
      # - `cached_content:` a `Cache` or cache name made with `client.caches`; the prompt holds only what follows it
      # - `cache: :system` caches the system prompt and tools
      # - `cache: true` also caches every message before the last one
      # - `cache: { ttl: 600 }` as `true`, with a TTL in seconds (default 300); add `scope: :system` for `:system`
      #
      # @raise [ArgumentError] for an invalid cache option, or a `cached_content:` that doesn't fit the request
      def initialize(prompt = nil, client:, model:, **, &)
        super(prompt, client: client.for_model(model), model:, **, &)
        @cache = cache_option
        @cache_use = explicit_cache_use
      end

    protected

      # Rounds of a tool-call loop reuse the first round's cache, so a loop doesn't create one cache per round.
      #
      # @param prompt [OmniAI::Chat::Prompt]
      #
      # @return [Chat]
      def spawn!(prompt)
        super.tap { |chat| chat.inherit_cache(@cache_use, @cache_key) if @cache }
      end

      # @param cache_use [Hash, nil]
      # @param cache_key [String, nil]
      def inherit_cache(cache_use, cache_key)
        @cache_use = cache_use
        @cache_key = cache_key
        @cache_resolved = true
      end

      # @return [Context]
      def context
        CONTEXT
      end

      # @return [HTTP::Response]
      def request!
        resolve_cache! if @cache && !@cache_resolved
        response = post!
        return response unless @cache && @cache_use && cache_gone?(response)

        CacheRegistry.instance.evict(@cache_key)
        @cache_use = nil
        post!
      end

      # @return [HTTP::Response]
      def post!
        @client
          .connection
          .accept(:json)
          .post(path, params: {
            key: (@client.api_key unless @client.credentials?),
            alt: ("sse" if stream?),
          }.compact, json: payload)
      end

      # `chat_options` is forwarded verbatim, so a key this class builds itself must be excluded or it is sent
      # twice — and `max_tokens` is OmniAI's normalized name, not one Gemini knows. Left in, it reaches the
      # wire as an unknown top-level field and the request fails with
      # `Invalid JSON payload received. Unknown name "max_tokens"`. `#generation_config` consumes it and
      # emits `maxOutputTokens` instead.
      #
      # @return [Hash]
      def payload
        return cached_payload if @cache_use

        OmniAI::Google.config.chat_options.except(:max_tokens).merge({
          system_instruction: @prompt.messages.find(&:system?)&.serialize(context:),
          contents: @prompt.messages.reject(&:system?).map { |message| message.serialize(context:) },
          tools:,
          generationConfig: generation_config,
        }).compact
      end

      # The system prompt and tools live in the cache, so neither is sent; tools still run locally.
      #
      # @return [Hash]
      def cached_payload
        OmniAI::Google.config.chat_options.except(:max_tokens, *CACHE_EXCLUDED_KEYS).merge({
          cachedContent: @cache_use[:name],
          contents: @prompt.messages.reject(&:system?).drop(@cache_use[:skip]).map do |message|
            message.serialize(context:)
          end,
          generationConfig: generation_config,
        }).compact
      end

      # @return [Hash]
      def tools
        self.class.serialize_tools(@tools)
      end

      # @return [Hash, nil] `{ scope: :system | :all, ttl: Integer }`
      def cache_option
        cache = @options[:cache]
        return unless cache

        raise ArgumentError, "pass `cache:` or `cached_content:`, not both" if @options[:cached_content]

        option =
          case cache
          when true then { scope: :all }
          when :system then { scope: :system }
          when Hash then { scope: :all }.merge(cache.slice(:scope, :ttl))
          else raise ArgumentError, "unsupported cache=#{cache.inspect}"
          end
        option[:ttl] = Integer(option[:ttl] || Cache::DEFAULT_TTL)
        scope = option[:scope]
        raise ArgumentError, "unsupported cache scope=#{scope.inspect}" unless %i[all system].include?(scope)

        option
      end

      # @raise [ArgumentError]
      #
      # @return [Hash, nil]
      def explicit_cache_use
        cached = @options[:cached_content]
        return unless cached

        if @prompt.messages.any?(&:system?)
          raise ArgumentError, "a cached chat can't send a system message; put it in the cache"
        end

        name = cached.is_a?(Cache) ? cached.name : cached
        check_cache_location!(name)
        check_cache!(cached) if cached.is_a?(Cache)

        { name:, skip: 0 }
      end

      # @param name [String]
      #
      # @raise [ArgumentError]
      def check_cache_location!(name)
        location_id = Cache.location_id(name)
        return if location_id.nil? || location_id.eql?(@client.location_id)

        raise ArgumentError, "cache location=#{location_id} doesn't match the request location=#{@client.location_id}"
      end

      # @param cache [Cache]
      #
      # @raise [ArgumentError]
      def check_cache!(cache)
        if cache.model && !cache.model.split("/").last.eql?(@model)
          raise ArgumentError, "cache model=#{cache.model} doesn't match model=#{@model}"
        end

        return if cache.tool_names.nil?

        missing = Array(@tools).grep(OmniAI::Tool).map(&:name) - cache.tool_names
        raise ArgumentError, "tools #{missing.join(', ')} are not declared in the cache" if missing.any?
      end

      # Finds or creates the cache for this prompt's cacheable part (`cache:`). Sends uncached when there is nothing
      # to cache, the model or prompt can't be cached, or a create is still pending after `config.cache_wait`.
      def resolve_cache!
        @cache_resolved = true
        messages = @prompt.messages.reject(&:system?)
        cached = @cache[:scope].eql?(:system) ? [] : messages[0...-1]
        prompt = OmniAI::Chat::Prompt.new(messages: [@prompt.messages.find(&:system?), *cached].compact)
        return if prompt.messages.empty? && !tools?

        ttl = @cache[:ttl]
        body = Cache.payload(client: @client, model: @model, prompt:, tools: @tools, ttl:).except(:ttl)
        @cache_key = Digest::SHA256.hexdigest(JSON.generate([@client.host, body]))

        name = CacheRegistry.instance.fetch(@cache_key, client: @client, ttl:,
          wait: OmniAI::Google.config.cache_wait) do
          Cache.create(prompt, client: @client, model: @model, ttl:, tools: @tools)
        end
        @cache_use = { name:, skip: cached.length } if name
      end

      # @param response [HTTP::Response]
      #
      # @return [Boolean]
      def cache_gone?(response)
        return true if response.status.not_found?
        return false unless response.status.client_error?

        status = error_status(response)
        CACHE_GONE_STATUSES.include?(status) || (status.eql?(CACHE_CHECK_STATUS) && cache_missing?)
      end

      # @param response [HTTP::Response]
      #
      # @return [String, nil] e.g. "NOT_FOUND"
      def error_status(response)
        JSON.parse(response.body.to_s).dig("error", "status")
      rescue JSON::ParserError
        nil
      end

      # @return [Boolean] true when a `get` of the cache in use returns 404
      def cache_missing?
        Cache.get(@cache_use[:name], client: @client)
        false
      rescue HTTPError => e
        e.response.status.not_found?
      rescue StandardError
        false
      end

      # @return [Hash]
      def generation_config
        data =
          case @format
          when :json then { responseMimeType: ResponseMimeType::JSON }
          when :text then { responseMimeType: ResponseMimeType::TEXT }
          when OmniAI::Schema::Format
            {
              responseMimeType: ResponseMimeType::SCHEMA,
              responseSchema: @format.schema.serialize(additional_properties: nil),
            }
          else {}
          end

        data[:temperature] = @temperature if @temperature
        data[:thinkingConfig] = thinking_config if @options[:thinking]
        data[:maxOutputTokens] = max_tokens if max_tokens

        data = data.compact
        data unless data.empty?
      end

      # A per-call `max_tokens:`, falling back to `config.chat_options[:max_tokens]` so a cap can also be set
      # globally — the same precedence omniai-anthropic applies. The value is passed through unchanged: no
      # floor is imposed, so the number a caller asks for is the number that reaches the wire.
      #
      # Note that Gemini spends this budget on thinking BEFORE emitting an answer, unlike Anthropic's
      # answer-only ceiling. A cap sized to the expected answer alone will be consumed by thinking on any
      # request the model reasons about, returning `finishReason: MAX_TOKENS` with little or no text. Size it
      # as thinking headroom plus expected answer.
      #
      # @return [Integer, nil]
      def max_tokens
        @options[:max_tokens] || OmniAI::Google.config.chat_options[:max_tokens]
      end

      # @return [String]
      def path
        "#{@client.path}/models/#{@model}:#{operation}"
      end

      # @return [String]
      def operation
        stream? ? "streamGenerateContent" : "generateContent"
      end

      # @return [Hash, nil]
      def thinking_config
        thinking = @options[:thinking]
        return unless thinking
        return { includeThoughts: true } unless thinking.is_a?(Hash)

        config = { includeThoughts: true }
        return config.merge(thinking) unless thinking.key?(:effort)

        config[:thinkingLevel] = thinking[:effort].upcase if thinking[:effort]
        config
      end

      # @return [Array<Message>]
      def build_tool_call_messages(tool_call_list)
        content = tool_call_list.map do |tool_call|
          ToolCallResult.new(tool_call_id: tool_call.id, content: execute_tool_call(tool_call), **tool_call.options)
        end

        [Message.new(role: "function", content:)]
      end
    end
  end
end

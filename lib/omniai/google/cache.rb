# frozen_string_literal: true

module OmniAI
  module Google
    # An explicit context cache (`cachedContents`). Usage:
    #
    #   cache = client.caches.create(model: "gemini-3.8-flash", ttl: 600) do |prompt|
    #     prompt.system("...")
    #     prompt.user("...")
    #   end
    #   client.chat("...", model: "gemini-3.8-flash", cached_content: cache.name)
    #   cache.delete
    class Cache
      DEFAULT_TTL = 300

      # @!attribute [r] data
      #   @return [Hash] the raw `cachedContents` resource
      attr_reader :data

      # @param prompt [OmniAI::Chat::Prompt, String, nil] optional
      # @param client [Client] required - already located for the model
      # @param model [String] required
      # @param ttl [Integer] optional - seconds
      # @param tools [Array<OmniAI::Tool>, nil] optional
      #
      # @yield [prompt] optional
      # @yieldparam prompt [OmniAI::Chat::Prompt]
      #
      # @raise [HTTPError]
      #
      # @return [Cache]
      def self.create(prompt = nil, client:, model:, ttl: DEFAULT_TTL, tools: nil, &block)
        prompt = prompt ? OmniAI::Chat::Prompt.parse(prompt) : OmniAI::Chat::Prompt.new
        block&.call(prompt)

        data = request!(client, :post, client.cache_path, payload(client:, model:, prompt:, tools:, ttl:))
        new(client:, data:, tool_names: Array(tools).grep(OmniAI::Tool).map(&:name))
      end

      # @param name [String]
      # @param client [Client]
      #
      # @raise [HTTPError]
      #
      # @return [Cache]
      def self.get(name, client:)
        new(client:, data: request!(client, :get, client.cache_path(name)))
      end

      # @param name [String]
      # @param client [Client]
      #
      # @raise [HTTPError]
      def self.delete(name, client:)
        request!(client, :delete, client.cache_path(name))
        nil
      end

      # @param name [String]
      #
      # @return [String, nil] e.g. "us" for "projects/P/locations/us/cachedContents/123"
      def self.location_id(name)
        name[%r{\Aprojects/[^/]+/locations/([^/]+)/}, 1]
      end

      # Serialized with the chat CONTEXT, so the cached part is byte-identical to what chat would send.
      #
      # @return [Hash]
      def self.payload(client:, model:, prompt:, tools:, ttl:)
        system = prompt.messages.find(&:system?)
        contents = prompt.messages.reject(&:system?).map { |message| message.serialize(context: Chat::CONTEXT) }

        {
          model: client.model_name(model),
          systemInstruction: system&.serialize(context: Chat::CONTEXT),
          contents: (contents unless contents.empty?),
          tools: Chat.serialize_tools(tools),
          ttl: "#{Integer(ttl)}s",
        }.compact
      end

      # @raise [HTTPError]
      #
      # @return [Hash]
      def self.request!(client, method, path, json = nil, params: {})
        params = params.merge(key: (client.api_key unless client.credentials?)).compact
        response = client.connection.accept(:json).request(method, path, params:, json:)

        raise HTTPError, response.flush unless response.status.ok?

        body = response.body.to_s
        body.strip.empty? ? {} : JSON.parse(body)
      end

      # @!attribute [r] tool_names
      #   @return [Array<String>, nil] the tools the cache was created with; nil when unknown (e.g. from `get`)
      attr_reader :tool_names

      # @param client [Client]
      # @param data [Hash]
      # @param tool_names [Array<String>, nil]
      def initialize(client:, data:, tool_names: nil)
        @client = client
        @data = data
        @tool_names = tool_names
      end

      # @return [String] e.g. "projects/P/locations/L/cachedContents/123" or "cachedContents/123"
      def name
        @data["name"]
      end

      # @return [String]
      def model
        @data["model"]
      end

      # @return [Time, nil]
      def expire_time
        Time.parse(@data["expireTime"]) if @data["expireTime"]
      end

      # @return [String, nil]
      def location_id
        self.class.location_id(name)
      end

      # @return [Integer, nil]
      def token_count
        @data.dig("usageMetadata", "totalTokenCount")
      end

      # @param ttl [Integer] seconds from now
      #
      # @raise [HTTPError]
      #
      # @return [Cache]
      def update(ttl:)
        @data = self.class.request!(@client, :patch, @client.cache_path(name), { ttl: "#{Integer(ttl)}s" },
          params: { updateMask: "ttl" })
        self
      end

      # @raise [HTTPError]
      def delete
        self.class.delete(name, client: @client)
      end
    end
  end
end

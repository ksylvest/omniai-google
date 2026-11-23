# frozen_string_literal: true

module OmniAI
  module Google
    # `client.caches`: create, get and delete explicit context caches.
    class Caches
      # @param client [Client]
      def initialize(client:)
        @client = client
      end

      # The cache is created at the model's location, the same host `client.chat` uses for that model.
      #
      # @param prompt [OmniAI::Chat::Prompt, String, nil] optional
      # @param model [String] required
      # @param ttl [Integer] optional - seconds
      # @param tools [Array<OmniAI::Tool>, nil] optional - declarations live in the cache; a cached chat can't send them
      #
      # @yield [prompt] optional
      # @yieldparam prompt [OmniAI::Chat::Prompt]
      #
      # @raise [HTTPError]
      #
      # @return [Cache]
      def create(prompt = nil, model:, ttl: Cache::DEFAULT_TTL, tools: nil, &)
        Cache.create(prompt, client: @client.for_model(model), model:, ttl:, tools:, &)
      end

      # @param name [String]
      #
      # @raise [HTTPError]
      #
      # @return [Cache]
      def get(name)
        Cache.get(name, client: @client.for_cache(name))
      end

      # @param name [String]
      #
      # @raise [HTTPError]
      def delete(name)
        Cache.delete(name, client: @client.for_cache(name))
      end
    end
  end
end

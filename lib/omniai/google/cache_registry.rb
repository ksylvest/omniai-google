# frozen_string_literal: true

module OmniAI
  module Google
    # Per-process bookkeeping for `cache:`. Creates and TTL refreshes run on a background thread, one per key, so a
    # slow create (the first one in a project has taken ~2 min) never blocks a chat for longer than `wait`.
    class CacheRegistry
      PREFIX = "omniai-google/cache/"

      # A store entry expires this many seconds before the cache itself, so a hit always has time left.
      MARGIN = 30

      # 4xx statuses that are worth retrying later; any other 4xx on create marks the key uncacheable for the TTL.
      TRANSIENT = [408, 429].freeze

      # @return [CacheRegistry]
      def self.instance
        INSTANCE
      end

      def initialize
        @mutex = Mutex.new
        @pending = {}
      end

      # @param key [String]
      # @param client [Client] located for the model; used to refresh the TTL
      # @param ttl [Integer] seconds
      # @param wait [Numeric] seconds
      #
      # @yieldreturn [Cache] creates the cache
      #
      # @return [String, nil] a cache name, or nil to send uncached
      def fetch(key, client:, ttl:, wait:, &create)
        entry = store.read(PREFIX + key)
        return hit(key, entry, client:) if entry.is_a?(Hash) && entry["name"]
        return if entry

        thread = background(key) { create!(key, ttl:, logger: client.logger, &create) }
        thread.value if thread.join(wait)
      end

      # @param key [String]
      def evict(key)
        store.delete(PREFIX + key)
      end

    private

      # @return [#read, #write, #delete]
      def store
        OmniAI::Google.config.cache_store
      end

      # @return [Float]
      def now
        Time.now.to_f
      end

      # Starts the block on a thread unless one is already running for the key; either way returns that thread.
      # A thread inherited across a fork is dead and its `ensure` never runs in the child, so it is replaced.
      #
      # @return [Thread]
      def background(key, &block)
        @mutex.synchronize do
          @pending.delete(key) unless @pending[key]&.alive?
          @pending[key] ||= Thread.new do
            block.call
          ensure
            @mutex.synchronize { @pending.delete(key) }
          end
        end
      end

      # @return [String, nil]
      def create!(key, ttl:, logger:)
        cache = yield
        write(key, cache.name, ttl)
        cache.name
      rescue HTTPError => e
        status = e.response.status.to_i
        if status.between?(400, 499) && !TRANSIENT.include?(status)
          store.write(PREFIX + key, { "uncacheable" => status }, expires_in: ttl)
        end
        logger&.warn("OmniAI::Google cache create failed status=#{status}")
        nil
      rescue StandardError => e
        logger&.warn("OmniAI::Google cache create failed error=#{e.class}")
        nil
      end

      # Extends the TTL in the background once less than half of it is left.
      #
      # @return [String]
      def hit(key, entry, client:)
        name = entry["name"]
        ttl = entry["ttl"]
        background("refresh/#{key}") { refresh!(key, name, ttl, client:) } if entry["expires_at"] - now < ttl / 2.0
        name
      end

      # A refresh that fails with a 4xx evicts the key, so the next chat creates a new cache.
      def refresh!(key, name, ttl, client:)
        Cache.new(client:, data: { "name" => name }).update(ttl:)
        write(key, name, ttl)
      rescue HTTPError => e
        evict(key) if e.response.status.client_error?
        client.logger&.warn("OmniAI::Google cache refresh failed status=#{e.response.status.to_i}")
      rescue StandardError => e
        client.logger&.warn("OmniAI::Google cache refresh failed error=#{e.class}")
      end

      # @param key [String]
      # @param name [String]
      # @param ttl [Integer]
      def write(key, name, ttl)
        store.write(PREFIX + key, { "name" => name, "ttl" => ttl, "expires_at" => now + ttl },
          expires_in: [ttl - MARGIN, 1].max)
      end

      INSTANCE = new
      private_constant :INSTANCE
    end
  end
end

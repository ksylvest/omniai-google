# frozen_string_literal: true

module OmniAI
  module Google
    # The default per-process store for `cache:`. Any object with `read(key)`, `write(key, value, expires_in:)` and
    # `delete(key)` can replace it via `config.cache_store` (e.g. `Rails.cache`).
    class CacheStore
      def initialize
        @entries = {}
        @mutex = Mutex.new
      end

      # @param key [String]
      #
      # @return [Object, nil]
      def read(key)
        @mutex.synchronize do
          value, expires_at = @entries[key]
          next value if expires_at && expires_at > now

          @entries.delete(key)
          nil
        end
      end

      # @param key [String]
      # @param value [Object]
      # @param expires_in [Numeric] seconds
      def write(key, value, expires_in:)
        @mutex.synchronize { @entries[key] = [value, now + expires_in] }
      end

      # @param key [String]
      def delete(key)
        @mutex.synchronize { @entries.delete(key) }
      end

    private

      # @return [Float]
      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end

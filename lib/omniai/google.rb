# frozen_string_literal: true

require "googleauth"
require "event_stream_parser"
require "omniai"
require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.push_dir(__dir__, namespace: OmniAI)
loader.setup

module OmniAI
  # A namespace for everything Google.
  module Google
    # @return [OmniAI::Google::Config]
    def self.config
      @config ||= Config.new
    end

    # @yield [OmniAI::Google::Config]
    def self.configure
      yield config
    end
  end
end

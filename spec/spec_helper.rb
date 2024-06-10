# frozen_string_literal: true

require 'webmock/rspec'

require 'omniai/google'

OmniAI::Google.configure do |config|
  config.api_key = '...'
end

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

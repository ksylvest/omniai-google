# frozen_string_literal: true

RSpec.describe OmniAI::Google::CacheRegistry do
  let(:registry) { described_class.instance }
  let(:client) { OmniAI::Google::Client.new }
  let(:cache) { OmniAI::Google::Cache.new(client:, data: { "name" => "cachedContents/abc" }) }

  before { OmniAI::Google.config.cache_store = OmniAI::Google::CacheStore.new }

  # After a fork the child inherits the parent's pending thread dead, and its `ensure` never runs.
  it "replaces a dead pending thread" do
    registry.instance_variable_get(:@pending)["key"] = Thread.new { nil }.tap(&:join)
    expect(registry.fetch("key", client:, ttl: 300, wait: 1) { cache }).to eql("cachedContents/abc")
  end
end

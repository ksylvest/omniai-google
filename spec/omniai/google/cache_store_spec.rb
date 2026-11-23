# frozen_string_literal: true

RSpec.describe OmniAI::Google::CacheStore do
  subject(:store) { described_class.new }

  it "reads what it wrote" do
    store.write("k", { "name" => "n" }, expires_in: 60)
    expect(store.read("k")).to eql({ "name" => "n" })
  end

  it "expires entries" do
    store.write("k", "v", expires_in: 0)
    expect(store.read("k")).to be_nil
  end

  it "deletes entries" do
    store.write("k", "v", expires_in: 60)
    store.delete("k")
    expect(store.read("k")).to be_nil
  end

  it "misses unknown keys" do
    expect(store.read("missing")).to be_nil
  end

  it "is the default config store" do
    expect(OmniAI::Google::Config.new.cache_store).to be_a(described_class)
  end
end

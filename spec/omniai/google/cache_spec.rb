# frozen_string_literal: true

RSpec.describe OmniAI::Google::Cache do
  let(:gemini) { "https://generativelanguage.googleapis.com/v1beta" }
  let(:client) { OmniAI::Google::Client.new }
  let(:weather) do
    OmniAI::Tool.new(->(city:) { "Sunny in #{city}" }, name: "weather", description: "Weather",
      parameters: OmniAI::Schema.object(properties: { city: OmniAI::Schema.string }, required: %i[city]))
  end
  let(:declaration) { JSON.parse(weather.serialize(context: OmniAI::Google::Chat::CONTEXT).to_json) }
  let(:resource) do
    {
      name: "cachedContents/abc",
      model: "models/gemini-3.8-flash",
      expireTime: "2026-11-23T12:05:00Z",
      usageMetadata: { totalTokenCount: 5419 },
    }
  end

  describe "client.caches.create" do
    subject(:cache) do
      client.caches.create(model: "gemini-3.8-flash", ttl: 600, tools: [weather]) do |prompt|
        prompt.system("Be terse.")
        prompt.user("Static template.")
      end
    end

    before do
      stub_request(:post, "#{gemini}/cachedContents?key=...")
        .with(body: {
          model: "models/gemini-3.8-flash",
          systemInstruction: { role: "system", parts: [{ text: "Be terse." }] },
          contents: [{ role: "user", parts: [{ text: "Static template." }] }],
          tools: [{ function_declarations: [declaration] }],
          ttl: "600s",
        })
        .to_return_json(body: resource)
    end

    it { expect(cache.name).to eql("cachedContents/abc") }
    it { expect(cache.model).to eql("models/gemini-3.8-flash") }
    it { expect(cache.token_count).to be(5419) }
    it { expect(cache.expire_time).to eql(Time.utc(2026, 11, 23, 12, 5)) }
    it { expect(cache.tool_names).to eql(["weather"]) }
    it { expect(cache.location_id).to be_nil }
  end

  describe "client.caches.create with no messages" do
    it "omits contents and a missing expiry" do
      stub_request(:post, "#{gemini}/cachedContents?key=...")
        .with(body: { model: "models/gemini-3.8-flash", ttl: "300s" })
        .to_return_json(body: { name: "cachedContents/abc" })
      cache = client.caches.create(model: "gemini-3.8-flash")
      expect(cache.expire_time).to be_nil
    end

    it "accepts a prompt" do
      stub_request(:post, "#{gemini}/cachedContents?key=...")
        .with(body: hash_including(contents: [{ role: "user", parts: [{ text: "Hi" }] }]))
        .to_return_json(body: resource)
      expect(client.caches.create("Hi", model: "gemini-3.8-flash").name).to eql("cachedContents/abc")
    end
  end

  describe "client.caches.create with an error" do
    it "raises HTTPError" do
      stub_request(:post, "#{gemini}/cachedContents?key=...").to_return(status: 400, body: "{}")
      expect { client.caches.create(model: "gemini-3.8-flash") }.to raise_error(OmniAI::HTTPError)
    end
  end

  describe "client.caches.get" do
    it "fetches the cache" do
      stub_request(:get, "#{gemini}/cachedContents/abc?key=...").to_return_json(body: resource)
      cache = client.caches.get("cachedContents/abc")
      expect(cache.tool_names).to be_nil
    end
  end

  describe "client.caches.delete" do
    it "deletes the cache" do
      stub = stub_request(:delete, "#{gemini}/cachedContents/abc?key=...").to_return(body: "")
      client.caches.delete("cachedContents/abc")
      expect(stub).to have_been_requested
    end
  end

  describe "#update" do
    it "patches the TTL" do
      stub_request(:patch, "#{gemini}/cachedContents/abc?key=...&updateMask=ttl")
        .with(body: { ttl: "900s" })
        .to_return_json(body: resource.merge(expireTime: "2026-11-23T12:15:00Z"))
      cache = described_class.new(client:, data: { "name" => "cachedContents/abc" })
      expect(cache.update(ttl: 900).expire_time).to eql(Time.utc(2026, 11, 23, 12, 15))
    end
  end

  describe "#delete" do
    it "deletes the cache" do
      stub = stub_request(:delete, "#{gemini}/cachedContents/abc?key=...").to_return(body: "{}")
      described_class.new(client:, data: { "name" => "cachedContents/abc" }).delete
      expect(stub).to have_been_requested
    end
  end

  context "with Vertex locations" do
    let(:credentials) do
      instance_double(Google::Auth::ServiceAccountCredentials, fetch_access_token!: nil, access_token: "token")
    end
    let(:client) do
      OmniAI::Google::Client.new(project_id: "p", credentials:, locations: { "gemini-3.8-flash" => "us" })
    end
    let(:us) { "https://aiplatform.us.rep.googleapis.com/v1" }
    let(:name) { "projects/123/locations/us/cachedContents/abc" }

    it "creates the cache at the model's location" do
      stub_request(:post, "#{us}/projects/p/locations/us/cachedContents")
        .with(body: hash_including(model: "projects/p/locations/us/publishers/google/models/gemini-3.8-flash"))
        .to_return_json(body: { name: })
      cache = client.caches.create("Hi", model: "gemini-3.8-flash")
      expect(cache.location_id).to eql("us")
    end

    it "gets a cache at the location in its name" do
      stub_request(:get, "#{us}/#{name}").to_return_json(body: { name: })
      expect(client.caches.get(name).name).to eql(name)
    end

    it "deletes a cache at the location in its name" do
      stub = stub_request(:delete, "#{us}/#{name}").to_return(body: "")
      client.caches.delete(name)
      expect(stub).to have_been_requested
    end

    it "raises for a name with no location" do
      expect { client.caches.get("cachedContents/abc") }.to raise_error(ArgumentError, /no location/)
    end
  end
end

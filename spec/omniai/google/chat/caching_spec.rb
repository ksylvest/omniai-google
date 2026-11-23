# frozen_string_literal: true

RSpec.describe OmniAI::Google::Chat, "caching" do # rubocop:disable RSpec/DescribeMethod
  let(:client) { OmniAI::Google::Client.new }
  let(:model) { "gemini-3.8-flash" }
  let(:base) { "https://generativelanguage.googleapis.com/v1beta" }
  let(:generate) { "#{base}/models/#{model}:generateContent?key=..." }
  let(:stream_url) { "#{base}/models/#{model}:streamGenerateContent?alt=sse&key=..." }
  let(:create_url) { "#{base}/cachedContents?key=..." }
  let(:ok) { { candidates: [{ content: { role: "model", parts: [{ text: "Hi" }] }, finishReason: "STOP" }] } }
  let(:sse) { "data: #{JSON.generate(ok)}\n\n" }
  let(:weather) do
    OmniAI::Tool.new(->(city:) { "Sunny in #{city}" }, name: "weather", description: "Weather",
      parameters: OmniAI::Schema.object(properties: { city: OmniAI::Schema.string }, required: %i[city]))
  end
  let(:declaration) { JSON.parse(weather.serialize(context: described_class::CONTEXT).to_json) }
  let(:prompt) do
    OmniAI::Chat::Prompt.build do |prompt|
      prompt.system("Be terse.")
      prompt.user("Static template.")
      prompt.user("Page 1.")
    end
  end

  def user(text) = { role: "user", parts: [{ text: }] }

  def body_of(request) = JSON.parse(request.body, symbolize_names: true)

  before do
    OmniAI::Google.config.cache_store = OmniAI::Google::CacheStore.new
    OmniAI::Google.config.cache_wait = 5
  end

  after { OmniAI::Google.config.cache_wait = 10 }

  describe "cached_content:" do
    it "sends cachedContent and no system or tools" do
      stub_request(:post, generate)
        .with(body: { cachedContent: "cachedContents/abc", contents: [user("Page 1.")] })
        .to_return_json(body: ok)
      expect(client.chat("Page 1.", model:, cached_content: "cachedContents/abc", tools: [weather]).text).to eql("Hi")
    end

    it "accepts a Cache" do
      cache = OmniAI::Google::Cache.new(client:, data: { "name" => "cachedContents/abc", "model" => "models/#{model}" })
      stub_request(:post,
        generate).with(body: hash_including(cachedContent: "cachedContents/abc")).to_return_json(body: ok)
      expect(client.chat("Page 1.", model:, cached_content: cache).text).to eql("Hi")
    end

    it "drops tool_config and system_instruction from chat_options" do
      allow(OmniAI::Google.config).to receive(:chat_options).and_return({ tool_config: {}, safetySettings: [] })
      stub_request(:post, generate)
        .with(body: { safetySettings: [], cachedContent: "cachedContents/abc", contents: [user("Page 1.")] })
        .to_return_json(body: ok)
      expect(client.chat("Page 1.", model:, cached_content: "cachedContents/abc").text).to eql("Hi")
    end

    it "runs tools locally and keeps the cache across a tool-call loop" do
      call = { candidates: [{ content: { role: "model",
                                         parts: [{ functionCall: { name: "weather", args: { city: "Paris" } } }], } }] }
      stub_request(:post, generate).to_return_json(body: call).then.to_return_json(body: ok)
      cache = OmniAI::Google::Cache.new(client:, data: { "name" => "cachedContents/abc" }, tool_names: ["weather"])
      client.chat("Weather?", model:, cached_content: cache, tools: [weather])
      expect(a_request(:post, generate).with do |r|
        body_of(r)[:cachedContent] && !body_of(r).key?(:tools) && body_of(r)[:contents].length == 3
      end).to have_been_made
    end

    it "raises for a system message" do
      expect { client.chat(prompt, model:, cached_content: "cachedContents/abc") }
        .to raise_error(ArgumentError, /system message/)
    end

    it "raises for a cache made for another model" do
      cache = OmniAI::Google::Cache.new(client:,
        data: { "name" => "cachedContents/abc", "model" => "models/gemini-3.7-flash" })
      expect { client.chat("Hi", model:, cached_content: cache) }.to raise_error(ArgumentError, /model/)
    end

    it "raises for a tool the cache doesn't declare" do
      cache = OmniAI::Google::Cache.new(client:, data: { "name" => "cachedContents/abc" }, tool_names: [])
      expect { client.chat("Hi", model:, cached_content: cache, tools: [weather]) }
        .to raise_error(ArgumentError, /weather/)
    end

    it "raises for a cache at another location" do
      credentials = instance_double(Google::Auth::ServiceAccountCredentials, fetch_access_token!: nil,
        access_token: "t")
      vertex = OmniAI::Google::Client.new(project_id: "p", credentials:, locations: { model => "us" })
      expect { vertex.chat("Hi", model:, cached_content: "projects/1/locations/eu/cachedContents/abc") }
        .to raise_error(ArgumentError, /location=eu/)
    end

    it "raises alongside cache:" do
      expect { client.chat("Hi", model:, cache: true, cached_content: "cachedContents/abc") }
        .to raise_error(ArgumentError, /not both/)
    end

    it "does not retry when the cache is gone" do
      stub_request(:post, generate).to_return(status: 404, body: "{}")
      expect { client.chat("Hi", model:, cached_content: "cachedContents/abc") }.to raise_error(OmniAI::HTTPError)
    end
  end

  describe "cache:" do
    let(:created) { { name: "cachedContents/abc", model: "models/#{model}" } }

    it "raises for an unsupported value" do
      expect { client.chat("Hi", model:, cache: :all) }.to raise_error(ArgumentError, /unsupported cache/)
    end

    it "raises for an unsupported scope" do
      expect { client.chat("Hi", model:, cache: { scope: :tools }) }.to raise_error(ArgumentError, /scope/)
    end

    context "with :system" do
      it "caches the system prompt and sends every message" do
        create = stub_request(:post, create_url)
          .with(body: { model: "models/#{model}",
                        systemInstruction: { role: "system", parts: [{ text: "Be terse." }] }, ttl: "300s", })
          .to_return_json(body: created)
        stub_request(:post, generate)
          .with(body: { cachedContent: "cachedContents/abc", contents: [user("Static template."), user("Page 1.")] })
          .to_return_json(body: ok)
        client.chat(prompt, model:, cache: :system)
        expect(create).to have_been_requested.once
      end
    end

    context "with true" do
      before do
        stub_request(:post, create_url)
          .with(body: hash_including(contents: [user("Static template.")]))
          .to_return_json(body: created)
        stub_request(:post, generate)
          .with(body: { cachedContent: "cachedContents/abc", contents: [user("Page 1.")] })
          .to_return_json(body: ok)
      end

      it "caches every message before the last one" do
        expect(client.chat(prompt, model:, cache: true).text).to eql("Hi")
      end

      it "reuses the cache" do
        2.times { client.chat(prompt, model:, cache: true) }
        expect(a_request(:post, create_url)).to have_been_made.once
      end
    end

    context "with a ttl" do
      it "creates the cache with it" do
        stub_request(:post, create_url).with(body: hash_including(ttl: "900s")).to_return_json(body: created)
        stub_request(:post,
          generate).with(body: hash_including(cachedContent: "cachedContents/abc")).to_return_json(body: ok)
        expect(client.chat(prompt, model:, cache: { ttl: 900 }).text).to eql("Hi")
      end

      it "scopes to the system prompt" do
        stub_request(:post, create_url).with(body: hash_including(ttl: "900s")).to_return_json(body: created)
        stub_request(:post, generate)
          .with(body: hash_including(contents: [user("Static template."), user("Page 1.")]))
          .to_return_json(body: ok)
        expect(client.chat(prompt, model:, cache: { ttl: 900, scope: :system }).text).to eql("Hi")
      end
    end

    it "sends uncached when there is nothing to cache" do
      stub_request(:post, generate).with(body: { contents: [user("Hi")] }).to_return_json(body: ok)
      client.chat("Hi", model:, cache: true)
      expect(a_request(:post, create_url)).not_to have_been_made
    end

    context "when the create fails with a 400" do
      before do
        stub_request(:post, create_url).to_return(status: 400, body: { error: { status: "INVALID_ARGUMENT" } }.to_json)
        stub_request(:post,
          generate).with(body: hash_including(system_instruction: { role: "system", parts: [{ text: "Be terse." }] }))
          .to_return_json(body: ok)
      end

      it "sends uncached and doesn't retry the create within the TTL" do
        2.times { client.chat(prompt, model:, cache: true) }
        expect(a_request(:post, create_url)).to have_been_made.once
      end
    end

    context "when the create fails with a 429" do
      before do
        stub_request(:post, create_url).to_return(status: 429, body: "{}")
        stub_request(:post, generate).to_return_json(body: ok)
      end

      it "sends uncached and retries the create next time" do
        2.times { client.chat(prompt, model:, cache: true) }
        expect(a_request(:post, create_url)).to have_been_made.twice
      end
    end

    context "when the create times out" do
      before do
        stub_request(:post, create_url).to_timeout
        stub_request(:post, generate).to_return_json(body: ok)
      end

      it "sends uncached" do
        expect(client.chat(prompt, model:, cache: true).text).to eql("Hi")
      end
    end

    context "when the create outlasts cache_wait" do
      before do
        OmniAI::Google.config.cache_wait = 0.05
        stub_request(:post, create_url).to_return do
          sleep 0.3
          { status: 200, body: created.to_json, headers: { "Content-Type" => "application/json" } }
        end
        stub_request(:post, generate).to_return_json(body: ok)
      end

      it "sends uncached, then uses the cache once the create finishes" do
        client.chat(prompt, model:, cache: true)
        expect(a_request(:post, generate).with { |r| !body_of(r).key?(:cachedContent) }).to have_been_made.once
        sleep 0.5
        client.chat(prompt, model:, cache: true)
        expect(a_request(:post,
          generate).with(body: hash_including(cachedContent: "cachedContents/abc"))).to have_been_made.once
      end
    end

    context "when the cache is gone" do
      before do
        stub_request(:post, create_url).to_return_json(body: created)
        stub_request(:post, generate).with(body: hash_including(cachedContent: "cachedContents/abc"))
          .to_return(status: 404, body: { error: { status: "NOT_FOUND" } }.to_json)
        stub_request(:post, generate).with(body: hash_including(contents: [user("Static template."), user("Page 1.")]))
          .to_return_json(body: ok)
      end

      it "retries once uncached" do
        expect(client.chat(prompt, model:, cache: true).text).to eql("Hi")
      end

      it "evicts the cache so the next chat creates one" do
        2.times { client.chat(prompt, model:, cache: true) }
        expect(a_request(:post, create_url)).to have_been_made.twice
      end
    end

    context "when the cached request fails with FAILED_PRECONDITION" do
      it "retries once uncached" do
        stub_request(:post, create_url).to_return_json(body: created)
        stub_request(:post, generate).with(body: hash_including(cachedContent: "cachedContents/abc"))
          .to_return(status: 400, body: { error: { status: "FAILED_PRECONDITION" } }.to_json)
        stub_request(:post,
          generate).with(body: hash_including(system_instruction: { role: "system", parts: [{ text: "Be terse." }] }))
          .to_return_json(body: ok)
        expect(client.chat(prompt, model:, cache: true).text).to eql("Hi")
      end
    end

    context "when the cached request fails with INVALID_ARGUMENT" do
      it "raises without retrying" do
        stub_request(:post, create_url).to_return_json(body: created)
        stub_request(:post, generate).to_return(status: 400, body: { error: { status: "INVALID_ARGUMENT" } }.to_json)
        expect { client.chat(prompt, model:, cache: true) }.to raise_error(OmniAI::HTTPError)
        expect(a_request(:post, generate)).to have_been_made.once
      end
    end

    context "when the cached request fails with a non-JSON 400" do
      it "raises without retrying" do
        stub_request(:post, create_url).to_return_json(body: created)
        stub_request(:post, generate).to_return(status: 400, body: "bad")
        expect { client.chat(prompt, model:, cache: true) }.to raise_error(OmniAI::HTTPError)
      end
    end

    context "when the cached request fails with a 500" do
      it "raises without retrying" do
        stub_request(:post, create_url).to_return_json(body: created)
        stub_request(:post, generate).to_return(status: 500, body: "{}")
        expect { client.chat(prompt, model:, cache: true) }.to raise_error(OmniAI::HTTPError)
      end
    end

    context "when streaming" do
      let(:stream) { proc {} }

      before { stub_request(:post, create_url).to_return_json(body: created) }

      it "streams a cached request" do
        stub_request(:post, stream_url)
          .with(body: { cachedContent: "cachedContents/abc", contents: [user("Page 1.")] })
          .to_return(body: sse)
        expect(client.chat(prompt, model:, cache: true, stream:).text).to eql("Hi")
      end

      it "retries once uncached when the cache is gone" do
        stub_request(:post, stream_url).with(body: hash_including(cachedContent: "cachedContents/abc"))
          .to_return(status: 404, body: "{}")
        stub_request(:post,
          stream_url).with(body: hash_including(system_instruction: { role: "system", parts: [{ text: "Be terse." }] }))
          .to_return(body: sse)
        expect(client.chat(prompt, model:, cache: true, stream:).text).to eql("Hi")
      end

      it "sends uncached when the create fails" do
        stub_request(:post, create_url).to_return(status: 400, body: "{}")
        stub_request(:post, stream_url).to_return(body: sse)
        expect(client.chat(prompt, model:, cache: true, stream:).text).to eql("Hi")
      end
    end

    context "with a tool-call loop" do
      let(:call) do
        { candidates: [{ content: { role: "model",
                                    parts: [{ functionCall: { name: "weather", args: { city: "Paris" } } }], } }] }
      end

      before do
        stub_request(:post, create_url)
          .with(body: hash_including(tools: [{ function_declarations: [declaration] }]))
          .to_return_json(body: created)
        stub_request(:post, generate).to_return_json(body: call).then.to_return_json(body: ok)
      end

      it "creates one cache and sends only the messages after it each round" do
        client.chat(prompt, model:, cache: true, tools: [weather])
        expect(a_request(:post, create_url)).to have_been_made.once
        expect(a_request(:post, generate).with { |r| body_of(r)[:cachedContent] && body_of(r)[:contents].length == 3 })
          .to have_been_made.once
      end

      it "sends the later rounds uncached once the cache is gone" do
        stub_request(:post, generate).to_return(status: 404, body: "{}").then
          .to_return_json(body: call).then.to_return_json(body: ok)
        client.chat(prompt, model:, cache: true, tools: [weather])
        expect(a_request(:post, generate).with { |r| body_of(r).key?(:tools) }).to have_been_made.twice
      end
    end

    context "with a cache near its expiry" do
      let(:key) { OmniAI::Google::CacheRegistry::PREFIX }

      before do
        stub_request(:post, create_url).to_return_json(body: created)
        stub_request(:post, generate).to_return_json(body: ok)
        client.chat(prompt, model:, cache: true)
        store = OmniAI::Google.config.cache_store
        entry_key = store.instance_variable_get(:@entries).keys.first
        store.write(entry_key, { "name" => "cachedContents/abc", "ttl" => 300, "expires_at" => Time.now.to_f + 60 },
          expires_in: 30)
      end

      def wait_for(stub)
        20.times do
          break if WebMock::RequestRegistry.instance.times_executed(stub.request_pattern).positive?

          sleep 0.05
        end
      end

      it "extends the TTL" do
        patch = stub_request(:patch, "#{base}/cachedContents/abc?key=...&updateMask=ttl").to_return_json(body: created)
        client.chat(prompt, model:, cache: true)
        wait_for(patch)
        expect(patch).to have_been_requested
      end

      it "evicts the cache when the refresh finds it gone" do
        patch = stub_request(:patch, "#{base}/cachedContents/abc?key=...&updateMask=ttl").to_return(status: 404,
          body: "{}")
        client.chat(prompt, model:, cache: true)
        wait_for(patch)
        sleep 0.05
        expect(OmniAI::Google.config.cache_store.instance_variable_get(:@entries)).to be_empty
      end

      it "keeps the cache when the refresh times out" do
        patch = stub_request(:patch, "#{base}/cachedContents/abc?key=...&updateMask=ttl").to_timeout
        client.chat(prompt, model:, cache: true)
        wait_for(patch)
        sleep 0.05
        expect(OmniAI::Google.config.cache_store.instance_variable_get(:@entries)).not_to be_empty
      end
    end
  end
end

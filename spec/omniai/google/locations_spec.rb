# frozen_string_literal: true

# `locations` maps each model to a Vertex location; every surface derives its host from that location.
RSpec.describe "Vertex locations" do # rubocop:disable RSpec/DescribeClass
  let(:credentials) do
    instance_double(Google::Auth::ServiceAccountCredentials, fetch_access_token!: nil, access_token: "token")
  end
  let(:locations) do
    {
      "gemini-3.8-flash" => "us",
      "gemini-embedding-001" => "us-central1",
      "gemini-3.5-transcribe" => "eu",
      "chirp_3" => "eu",
      "gemini-3.8-live" => "us",
    }
  end
  let(:client) { OmniAI::Google::Client.new(project_id: "test-project", credentials:, locations:) }
  let(:vertex) { "https://aiplatform.us.rep.googleapis.com/v1/projects/test-project/locations/us/publishers/google" }

  describe "chat" do
    let(:body) { { candidates: [{ content: { role: "model", parts: [{ text: "Hi" }] }, finishReason: "STOP" }] } }

    it "routes to the model's location" do
      stub_request(:post, "#{vertex}/models/gemini-3.8-flash:generateContent").to_return_json(body:)
      expect(client.chat("Hello", model: "gemini-3.8-flash").text).to eql("Hi")
    end

    it "routes a stream to the model's location" do
      stub_request(:post, "#{vertex}/models/gemini-3.8-flash:streamGenerateContent?alt=sse")
        .to_return(body: "data: #{JSON.generate(body)}\n\n")
      chunks = []
      client.chat("Hello", model: "gemini-3.8-flash", stream: proc { |chunk| chunks << chunk })
      expect(chunks).not_to be_empty
    end
  end

  describe "embed" do
    it "routes to the model's location" do
      stub_request(:post, "https://us-central1-aiplatform.googleapis.com/v1/projects/test-project/locations/" \
        "us-central1/publishers/google/models/gemini-embedding-001:predict")
        .to_return_json(body: { predictions: [{ embeddings: { values: [0.0], statistics: { token_count: 1 } } }] })
      expect(client.embed("Hello", model: "gemini-embedding-001").embedding).to eql([0.0])
    end
  end

  describe "transcribe" do
    it "sends a Gemini model to its mapped location as given" do
      url = "https://aiplatform.eu.rep.googleapis.com/v1/projects/test-project/locations/eu/publishers/google/" \
        "models/gemini-3.5-transcribe:generateContent"
      stub_request(:post, url).to_return_json(body: {
        candidates: [{ content: { role: "model", parts: [{ text: "Hi" }] }, finishReason: "STOP" }],
      })
      expect(client.transcribe("gs://bucket/a.wav", model: "gemini-3.5-transcribe").text).to eql("Hi")
    end

    it "sends a Chirp model to its mapped location as given" do
      stub_request(:post, "https://eu-speech.googleapis.com/v2/projects/test-project/locations/eu/recognizers/" \
        "_:batchRecognize")
        .to_return_json(body: { name: "operations/1" })
      stub_request(:get, "https://eu-speech.googleapis.com/v2/operations/1").to_return_json(body: {
        done: true,
        response: { results: { "gs://bucket/a.wav" => {
          transcript: { results: [{ alternatives: [{ transcript: "Hi" }] }] },
        } } },
      })
      expect(client.transcribe("gs://bucket/a.wav", model: "chirp_3").text).to eql("Hi")
    end
  end

  # Zonal entries would otherwise be remapped (Gemini to its multi-region, chirp_2 pinned to us-central1).
  context "with locations the gem would otherwise remap" do
    let(:locations) { { "gemini-3.5-transcribe" => "us-central1", "chirp_2" => "us" } }

    it "keeps a Gemini model's mapped location" do
      url = "https://us-central1-aiplatform.googleapis.com/v1/projects/test-project/locations/us-central1/" \
        "publishers/google/models/gemini-3.5-transcribe:generateContent"
      stub_request(:post, url).to_return_json(body: {
        candidates: [{ content: { role: "model", parts: [{ text: "Hi" }] }, finishReason: "STOP" }],
      })
      expect(client.transcribe("gs://bucket/a.wav", model: "gemini-3.5-transcribe").text).to eql("Hi")
    end

    it "keeps a Chirp model's mapped location" do
      stub_request(:post, "https://us-speech.googleapis.com/v2/projects/test-project/locations/us/recognizers/" \
        "_:batchRecognize")
        .to_return_json(body: { name: "operations/1" })
      stub_request(:get, "https://us-speech.googleapis.com/v2/operations/1").to_return_json(body: {
        done: true,
        response: { results: { "gs://bucket/a.wav" => {
          transcript: { results: [{ alternatives: [{ transcript: "Hi" }] }] },
        } } },
      })
      expect(client.transcribe("gs://bucket/a.wav", model: "chirp_2").text).to eql("Hi")
    end
  end

  describe "live" do
    it "connects to the model's location" do
      live = OmniAI::Google::Live.new(client:, model: "gemini-3.8-live")
      expect(live.send(:url)).to start_with("wss://aiplatform.us.rep.googleapis.com/ws/")
    end
  end

  context "with a model missing from the map" do
    it "raises before any request" do
      expect { client.chat("Hello", model: "gemini-2.5-flash") }
        .to raise_error(OmniAI::Google::UnknownLocationError) { |error| expect(error.model).to eql("gemini-2.5-flash") }
      expect(a_request(:any, //)).not_to have_been_made
    end

    it "names a defaulted model" do
      expect { client.embed("Hello") }.to raise_error(OmniAI::Google::UnknownLocationError) do |error|
        expect(error.model).to eql(OmniAI::Google::Embed::DEFAULT_MODEL)
      end
    end

    it "raises for live" do
      expect { OmniAI::Google::Live.new(client:, model: "gemini-2.5-flash-live") }
        .to raise_error(OmniAI::Google::UnknownLocationError)
    end
  end

  context "with an explicit host" do
    let(:client) do
      OmniAI::Google::Client.new(project_id: "test-project", location_id: "us-east4", credentials:, locations:,
        host: "https://us-east4-aiplatform.googleapis.com")
    end

    it "ignores the map" do
      stub_request(:post, "https://us-east4-aiplatform.googleapis.com/v1/projects/test-project/locations/us-east4/" \
        "publishers/google/models/gemini-2.5-flash:generateContent")
        .to_return_json(body: { candidates: [{ content: { role: "model", parts: [{ text: "Hi" }] } }] })
      expect(client.chat("Hello", model: "gemini-2.5-flash").text).to eql("Hi")
    end
  end

  context "when configured" do
    around do |example|
      OmniAI::Google.config.locations = locations
      example.run
    ensure
      OmniAI::Google.config.locations = nil
    end

    let(:client) { OmniAI::Google::Client.new(project_id: "test-project", credentials:) }

    it "uses the configured map" do
      expect { client.chat("Hello", model: "gemini-2.5-flash") }.to raise_error(OmniAI::Google::UnknownLocationError)
    end
  end
end

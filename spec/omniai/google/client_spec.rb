# frozen_string_literal: true

RSpec.describe OmniAI::Google::Client do
  subject(:client) { described_class.new(**options) }

  let(:options) { {} }

  describe "#chat" do
    it "proxies" do
      allow(OmniAI::Google::Chat).to receive(:process!)
      client.chat("Hello!")
      expect(OmniAI::Google::Chat).to have_received(:process!)
    end
  end

  describe "#embed" do
    it "proxies" do
      allow(OmniAI::Google::Embed).to receive(:process!)
      client.embed("Hello!")
      expect(OmniAI::Google::Embed).to have_received(:process!)
    end
  end

  describe "#upload" do
    let(:io) { StringIO.new("Hello!") }

    it "proxies" do
      allow(OmniAI::Google::Upload).to receive(:process!)
      client.upload(io)
      expect(OmniAI::Google::Upload).to have_received(:process!)
    end
  end

  describe "#path" do
    context "without options" do
      it "returns the path" do
        expect(client.path).to eq("/#{client.version}")
      end
    end

    context "with options" do
      let(:options) { { project_id: "manhattan", location_id: "us-east4" } }

      it "returns the path" do
        expect(client.path).to eq("/#{client.version}/projects/manhattan/locations/us-east4/publishers/google")
      end
    end
  end

  describe "#version" do
    context "with the default Gemini API host" do
      it "is the beta version" do
        expect(described_class.new(api_key: "fake").version).to eq(OmniAI::Google::Config::Version::BETA)
      end
    end

    context "with a Vertex host" do
      # `OmniAI::Google.config.version` derives from the config's host, not the client's, so a client built with a
      # Vertex host used to inherit `v1beta` and 404 against every regional endpoint.
      it "is the stable version" do
        client = described_class.new(api_key: "fake", host: "https://us-central1-aiplatform.googleapis.com")
        expect(client.version).to eq(OmniAI::Google::Config::Version::STABLE)
      end

      it "is the stable version for the multi-region endpoint" do
        client = described_class.new(api_key: "fake", host: "https://aiplatform.us.rep.googleapis.com")
        expect(client.version).to eq(OmniAI::Google::Config::Version::STABLE)
      end

      it "builds a v1 path for the multi-region endpoint" do
        client = described_class.new(
          api_key: "fake",
          host: "https://aiplatform.us.rep.googleapis.com",
          project_id: "manhattan",
          location_id: "us"
        )
        expect(client.path).to eq("/v1/projects/manhattan/locations/us/publishers/google")
      end

      it "builds a v1 path" do
        client = described_class.new(
          api_key: "fake",
          host: "https://us-central1-aiplatform.googleapis.com",
          project_id: "manhattan",
          location_id: "us-central1"
        )
        expect(client.path).to eq("/v1/projects/manhattan/locations/us-central1/publishers/google")
      end
    end

    context "with a custom non-Vertex host" do
      # A proxy or gateway in front of the Gemini API must keep deferring to the config, so this fix cannot
      # silently move those callers off the version they were using.
      it "defers to the configured version" do
        client = described_class.new(api_key: "fake", host: "https://gateway.example.com")
        expect(client.version).to eq(OmniAI::Google.config.version)
      end
    end

    context "with an explicit version" do
      it "is respected" do
        client = described_class.new(
          api_key: "fake",
          host: "https://us-central1-aiplatform.googleapis.com",
          version: "v1beta1"
        )
        expect(client.version).to eq("v1beta1")
      end
    end
  end

  describe "#vertex?" do
    # Google serves Vertex AI on three host shapes: the global endpoint, a region-prefixed endpoint, and the
    # multi-region `<geo>.rep` endpoint. Only the first two contain the literal "aiplatform.googleapis.com".
    [
      "https://aiplatform.googleapis.com",
      "https://us-central1-aiplatform.googleapis.com",
      "https://aiplatform.us.rep.googleapis.com",
    ].each do |host|
      it "is true for #{host}" do
        expect(described_class.new(api_key: "fake", host:)).to be_vertex
      end
    end

    it "is false for the Gemini API host" do
      expect(described_class.new(api_key: "fake", host: "https://generativelanguage.googleapis.com"))
        .not_to be_vertex
    end

    it "is false for a host that merely mentions a Vertex host elsewhere in the URL" do
      expect(described_class.new(api_key: "fake", host: "https://proxy.example.com/aiplatform.googleapis.com"))
        .not_to be_vertex
    end

    it "is false for a lookalike host outside googleapis.com" do
      expect(described_class.new(api_key: "fake", host: "https://aiplatform.googleapis.com.evil.example"))
        .not_to be_vertex
    end
  end

  describe "#connection" do
    context "without options" do
      it "returns an HTTP client" do
        expect(client.connection).to respond_to(:request)
      end
    end

    context "with options" do
      let(:options) { { credentials: } }
      let(:credentials) { instance_double(Google::Auth::ServiceAccountCredentials) }

      it "returns an HTTP client" do
        allow(credentials).to receive(:fetch_access_token!)
        allow(credentials).to receive(:access_token) { SecureRandom.alphanumeric }
        expect(client.connection).to respond_to(:request)
        expect(credentials).to have_received(:fetch_access_token!)
        expect(credentials).to have_received(:access_token)
      end
    end
  end
end

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

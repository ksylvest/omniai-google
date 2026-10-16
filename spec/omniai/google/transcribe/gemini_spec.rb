# frozen_string_literal: true

RSpec.describe OmniAI::Google::Transcribe::Gemini do
  let(:credentials) { instance_double(Google::Auth::ServiceAccountCredentials) }
  let(:location_id) { "us-central1" }
  let(:client) do
    OmniAI::Google::Client.new(project_id: "test-project", location_id:, credentials:,
      host: "https://us-central1-aiplatform.googleapis.com")
  end
  let(:model) { OmniAI::Google::Transcribe::Model::GEMINI_3_5_TRANSCRIBE }
  let(:wav) { "RIFF\x24\x00\x00\x00WAVEfmt #{"\x00" * 24}".b }
  let(:io) { StringIO.new(wav) }
  let(:format) { OmniAI::Transcribe::Format::JSON }
  let(:options) { {} }
  let(:url) do
    "https://aiplatform.us.rep.googleapis.com/v1/projects/test-project/locations/us/publishers/google/models/" \
      "gemini-3.5-transcribe:generateContent"
  end
  let(:parts) do
    [{ text: "Yes, I am working.", audioTranscription: { text: "Yes, I am working." } }]
  end

  before do
    allow(credentials).to receive(:fetch_access_token!)
    allow(credentials).to receive(:access_token).and_return("token")
    stub_request(:post, url).to_return_json(body: {
      candidates: [{ content: { role: "model", parts: }, finishReason: "STOP" }],
    })
  end

  describe ".process!" do
    subject(:transcription) { described_class.process!(io, client:, model:, format:, **options) }

    it "sends the audio inline to the us multi-region with the bearer token" do
      transcription
      expect(a_request(:post, url).with(
        headers: { "Authorization" => "Bearer token" },
        body: { contents: [{ role: "user", parts: [{ inlineData: { mimeType: "audio/wav",
                                                                   data: Base64.strict_encode64(wav), } }], }] }
      )).to have_been_made
    end

    it { expect(transcription.text).to eql("Yes, I am working.") }
    it { expect(transcription.model).to eql("gemini-3.5-transcribe") }
    it { expect(transcription.segments).to be_nil }

    context "with an european location_id" do
      let(:location_id) { "europe-west4" }
      let(:url) { super().sub("aiplatform.us.rep", "aiplatform.eu.rep").sub("locations/us/", "locations/eu/") }

      it { expect(transcription.text).to eql("Yes, I am working.") }
    end

    context "with the global location_id" do
      let(:location_id) { "global" }
      let(:url) { super().sub("aiplatform.us.rep", "aiplatform").sub("locations/us/", "locations/global/") }

      it { expect(transcription.text).to eql("Yes, I am working.") }
    end

    context "with options" do
      let(:options) { { language: "es-US", diarization: true, word_timestamps: true, vocabulary: %w[carpintero] } }

      it "sends them as the audio transcription config" do
        transcription
        expect(a_request(:post, url).with do |req|
          JSON.parse(req.body)["generationConfig"] == {
            "audioTranscriptionConfig" => {
              "languageCodes" => ["es-US"], "diarization" => true, "wordTimestamp" => true,
              "customVocabulary" => ["carpintero"],
            },
          }
        end).to have_been_made
      end
    end

    context "without options" do
      it "omits the generation config (auto-detects the language)" do
        transcription
        expect(a_request(:post, url).with { |req| !JSON.parse(req.body).key?("generationConfig") }).to have_been_made
      end
    end

    context "with a GCS URI" do
      let(:io) { "gs://bucket/interview.mp3" }

      it "sends it as file data" do
        transcription
        expect(a_request(:post, url).with do |req|
          JSON.parse(req.body).dig("contents", 0, "parts", 0) ==
            { "fileData" => { "fileUri" => "gs://bucket/interview.mp3", "mimeType" => "audio/mpeg" } }
        end).to have_been_made
      end
    end

    context "with a file larger than the inline limit" do
      let(:io) { StringIO.new(wav + ("\x00".b * described_class::INLINE_LIMIT)) }

      before do
        allow(OmniAI::Google::Bucket).to receive(:process!).and_return("gs://test-project-speech-audio/audio.wav")
        allow_any_instance_of(described_class).to receive(:cleanup_gcs_file) # rubocop:disable RSpec/AnyInstance
      end

      it "uploads it and sends it as file data" do
        transcription
        expect(a_request(:post, url).with do |req|
          JSON.parse(req.body).dig("contents", 0, "parts", 0) ==
            { "fileData" => { "fileUri" => "gs://test-project-speech-audio/audio.wav", "mimeType" => "audio/wav" } }
        end).to have_been_made
      end

      it "deletes the upload when the request fails" do
        stub_request(:post, url).to_return(status: 500, body: "{}")
        instance = described_class.new(io, client:, model:, format:)
        allow(instance).to receive(:cleanup_gcs_file)
        expect { instance.process! }.to raise_error(OmniAI::HTTPError)
        expect(instance).to have_received(:cleanup_gcs_file).with("gs://test-project-speech-audio/audio.wav")
      end
    end

    context "with an unrecognised audio format" do
      let(:io) { StringIO.new("not audio") }

      it { expect { transcription }.to raise_error(ArgumentError, /unrecognised audio format/) }
    end

    context "without credentials" do
      let(:client) { OmniAI::Google::Client.new(api_key: "fake", project_id: "test-project") }

      it { expect { transcription }.to raise_error(ArgumentError, /Vertex credentials/) }
    end

    context "with diarized parts and word timestamps (verbose_json)" do
      let(:format) { OmniAI::Transcribe::Format::VERBOSE_JSON }
      let(:parts) do
        [
          { text: "¿Está trabajando?", audioTranscription: { text: "¿Está trabajando?", speakerLabel: "spk:0" } },
          { text: "Sí, trabajo.", audioTranscription: {
            text: "Sí, trabajo.", speakerLabel: "spk:1",
            words: [
              { word: "Sí,", startOffset: "3.200s", endOffset: "3.500s" },
              { word: "trabajo.", startOffset: "3.600s", endOffset: "4.300s" },
            ],
          }, },
        ]
      end

      it { expect(transcription.text).to eql("¿Está trabajando? Sí, trabajo.") }

      it "returns one segment per part with speaker and word times" do
        expect(transcription.segments).to eql([
          { "id" => 0, "text" => "¿Está trabajando?", "speaker" => "spk:0" },
          { "id" => 1, "text" => "Sí, trabajo.", "speaker" => "spk:1", "start" => 3.2, "end" => 4.3,
            "words" => [
              { "word" => "Sí,", "start" => 3.2, "end" => 3.5 },
              { "word" => "trabajo.", "start" => 3.6, "end" => 4.3 },
            ], },
        ])
      end
    end

    context "when the response has no content" do
      before do
        stub_request(:post, url).to_return_json(body: { candidates: [{ finishReason: "PROHIBITED_CONTENT" }] })
      end

      it { expect { transcription }.to raise_error(OmniAI::Error, /no content \(finish reason PROHIBITED_CONTENT\)/) }
    end

    context "when the request fails" do
      before { stub_request(:post, url).to_return(status: 400, body: "{}") }

      it { expect { transcription }.to raise_error(OmniAI::HTTPError) }
    end
  end
end

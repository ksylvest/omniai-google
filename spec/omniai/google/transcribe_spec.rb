# frozen_string_literal: true

RSpec.describe OmniAI::Google::Transcribe do
  let(:client) { OmniAI::Google::Client.new(api_key: "fake", project_id: "test-project", location_id: "us-central1") }
  let(:model) { described_class::Model::LATEST_SHORT }

  describe ".process!" do
    subject(:transcription) { described_class.process!(path, client:, model:, format:) }

    let(:path) { Pathname.new(File.dirname(__FILE__)).join("..", "..", "fixtures", "greeting.txt") }

    context "with JSON format" do
      let(:format) { described_class::Format::JSON }

      before do
        stub_request(:post, "https://us-central1-speech.googleapis.com/v2/projects/test-project/locations/us-central1/recognizers/_:recognize?key=fake")
          .to_return_json(body: {
            results: [
              {
                alternatives: [
                  {
                    transcript: "The quick brown fox jumps over a lazy dog.",
                    confidence: 0.98,
                  },
                ],
              },
            ],
          })
      end

      it { expect(transcription.text).to eql("The quick brown fox jumps over a lazy dog.") }
    end

    context "with VERBOSE_JSON format" do
      let(:format) { described_class::Format::VERBOSE_JSON }

      before do
        stub_request(:post, "https://us-central1-speech.googleapis.com/v2/projects/test-project/locations/us-central1/recognizers/_:recognize?key=fake")
          .to_return_json(body: {
            results: [
              {
                alternatives: [
                  {
                    transcript: "The quick brown fox jumps over a lazy dog.",
                    confidence: 0.98,
                    words: [
                      { word: "The", startTime: "0s", endTime: "0.1s", confidence: 0.99 },
                      { word: "quick", startTime: "0.1s", endTime: "0.3s", confidence: 0.97 },
                    ],
                  },
                ],
              },
            ],
          })
      end

      it { expect(transcription.text).to eql("The quick brown fox jumps over a lazy dog.") }
    end

    context "with Vertex AI client" do
      let(:client) do
        OmniAI::Google::Client.new(api_key: "fake", project_id: "test-project", location_id: "us-central1",
          host: "https://us-central1-aiplatform.googleapis.com")
      end
      let(:format) { described_class::Format::JSON }

      before do
        stub_request(:post, "https://us-central1-speech.googleapis.com/v2/projects/test-project/locations/us-central1/recognizers/_:recognize?key=fake")
          .to_return_json(body: {
            results: [
              {
                alternatives: [
                  {
                    transcript: "Hello world from Vertex AI.",
                    confidence: 0.95,
                  },
                ],
              },
            ],
          })
      end

      it { expect(transcription.text).to eql("Hello world from Vertex AI.") }
    end
  end
end

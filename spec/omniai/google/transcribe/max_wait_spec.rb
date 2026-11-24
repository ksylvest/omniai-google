# frozen_string_literal: true

RSpec.describe OmniAI::Google::Transcribe, "max_wait" do # rubocop:disable RSpec/DescribeMethod
  let(:client) { OmniAI::Google::Client.new(api_key: "fake", project_id: "test-project", location_id: "us-central1") }
  let(:speech) { "https://us-central1-speech.googleapis.com/v2" }
  let(:operation) { "projects/test-project/locations/us-central1/operations/1" }
  let(:done) do
    {
      name: operation,
      done: true,
      response: { results: { "gs://bucket/a.wav" => {
        transcript: { results: [{ alternatives: [{ transcript: "Hi" }] }] },
        metadata: { totalBilledDuration: "300s" },
      } } },
    }
  end

  before do
    stub_request(:post, "#{speech}/projects/test-project/locations/us-central1/recognizers/_:batchRecognize?key=fake")
      .to_return_json(body: { name: operation })
    allow_any_instance_of(described_class).to receive(:sleep) # rubocop:disable RSpec/AnyInstance
  end

  context "when the operation isn't done within max_wait" do
    before { stub_request(:get, "#{speech}/#{operation}?key=fake").to_return_json(body: { name: operation }) }

    it "raises a TimeoutError with the operation and wait" do
      expect { client.transcribe("gs://bucket/a.wav", model: "latest_long", max_wait: 30) }
        .to raise_error(described_class::TimeoutError, "operation=#{operation} not done after 30s") do |error|
          expect(error).to have_attributes(operation_name: operation, wait: 30)
        end
    end

    it "is an OmniAI::Error" do
      expect { client.transcribe("gs://bucket/a.wav", model: "latest_long", max_wait: 30) }
        .to raise_error(OmniAI::Error)
    end

    it "polls for max_wait" do
      expect { client.transcribe("gs://bucket/a.wav", model: "latest_long", max_wait: 30) }
        .to raise_error(described_class::TimeoutError)
      expect(a_request(:get, "#{speech}/#{operation}?key=fake")).to have_been_made.twice
    end

    it "defaults to the estimate from the file size" do
      expect { client.transcribe("gs://bucket/a.wav", model: "latest_long") }
        .to raise_error(described_class::TimeoutError) { |error| expect(error.wait).to eq 600 }
    end
  end

  context "when the operation finishes" do
    subject(:transcription) { client.transcribe("gs://bucket/a.wav", model: "latest_long", max_wait: 1800) }

    before do
      stub_request(:get, "#{speech}/#{operation}?key=fake")
        .to_return_json(body: { name: operation }).then.to_return_json(body: done)
    end

    it { expect(transcription.text).to eql("Hi") }
    it { expect(transcription.operation_name).to eql(operation) }
    it { expect(transcription.billed_duration).to be(300.0) }
  end

  context "when a sync request reports billing" do
    it "sets billed_duration and no operation" do
      stub_request(:post, "#{speech}/projects/test-project/locations/us-central1/recognizers/_:recognize?key=fake")
        .to_return_json(body: {
          results: [{ alternatives: [{ transcript: "Hi" }] }],
          metadata: { totalBilledDuration: "5s" },
        })
      path = Pathname.new(File.dirname(__FILE__)).join("..", "..", "..", "fixtures", "greeting.txt")
      transcription = client.transcribe(path, model: "latest_short", max_wait: 1800)
      expect(transcription).to have_attributes(billed_duration: 5.0, operation_name: nil)
    end
  end

  it "is rejected by Gemini transcribe models" do
    expect { client.transcribe("gs://bucket/a.wav", model: "gemini-3.5-transcribe", max_wait: 30) }
      .to raise_error(ArgumentError, /max_wait/)
  end
end

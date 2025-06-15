# frozen_string_literal: true

RSpec.describe OmniAI::Google::Bucket do
  let(:client) { OmniAI::Google::Client.new(api_key: "fake", project_id: "test-project", location_id: "us") }
  let(:large_audio_file) { StringIO.new("a" * 15_000_000) } # 15MB file

  describe ".process!" do
    subject(:gcs_uri) { described_class.process!(client:, io: large_audio_file) }

    before do
      # Mock the Google Cloud Storage client
      storage_client = double
      bucket = double

      allow(Google::Cloud::Storage).to receive(:new).and_return(storage_client)
      allow(storage_client).to receive_messages(bucket:, create_bucket: bucket)
      allow(bucket).to receive(:create_file).and_return(true)

      # Allow time mocking for filename generation
      allow(Time).to receive(:now).and_return(Time.new(2023, 1, 1, 12, 0, 0))
      allow(SecureRandom).to receive(:hex).with(4).and_return("abcd")
    end

    it "returns a GCS URI" do
      expect(gcs_uri).to match(%r{^gs://test-project-speech-audio/audio_\d{8}_\d{6}_[a-f0-9]{4}\.wav$})
    end
  end

  describe "#needs_gcs_upload?" do
    let(:transcriber) { OmniAI::Google::Transcribe.new(test_file, client:, model: "latest_short") }

    context "with small file" do
      let(:test_file) { StringIO.new("small content") }

      it "returns false" do
        expect(transcriber.send(:needs_gcs_upload?)).to be false
      end
    end

    context "with large file" do
      let(:test_file) { StringIO.new("a" * 15_000_000) } # 15MB

      it "returns true" do
        expect(transcriber.send(:needs_gcs_upload?)).to be true
      end
    end

    context "with GCS URI" do
      let(:test_file) { "gs://existing-bucket/file.wav" }

      it "returns false" do
        expect(transcriber.send(:needs_gcs_upload?)).to be false
      end
    end
  end
end

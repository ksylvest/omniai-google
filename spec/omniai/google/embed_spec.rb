# frozen_string_literal: true

RSpec.describe OmniAI::Google::Embed do
  let(:client) { OmniAI::Google::Client.new }
  let(:project_id) { 'fake' }

  describe '.process!' do
    subject(:process!) { described_class.process!(content, client:, model:) }

    let(:content) { 'The quick brown fox jumps over a lazy dog.' }
    let(:model) { described_class::DEFAULT_MODEL }
    let(:location) { OmniAI::Google::Config::DEFAULT_LOCATION }

    before do
      stub_request(:post, "https://generativelanguage.googleapis.com/v1/models/#{model}:predict")
        .with(body: {
          instances: [{ content: }],
        })
        .to_return_json(body: {
          predictions: [
            {
              embeddings: {
                statistics: { token_count: 8 },
                values: [0.0],
              },
            },
          ],
        })
    end

    it { expect(process!).to be_a(OmniAI::Embed::Response) }
    it { expect(process!.embedding).to eql([0.0]) }
    it { expect(process!.usage.prompt_tokens).to be(8) }
    it { expect(process!.usage.total_tokens).to be(8) }
  end
end

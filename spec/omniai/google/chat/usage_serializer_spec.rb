# frozen_string_literal: true

RSpec.describe OmniAI::Google::Chat::UsageSerializer do
  let(:context) { OmniAI::Google::Chat::CONTEXT }

  describe '.deserialize' do
    subject(:deserialize) { described_class.deserialize(data, context:) }

    let(:data) do
      {
        'prompt_token_count' => 2,
        'candidates_token_count' => 3,
        'total_token_count' => 5,
      }
    end

    it { expect(deserialize).to be_a(OmniAI::Chat::Usage) }
  end

  describe '.serialize' do
    subject(:serialize) { described_class.serialize(usage, context:) }

    let(:usage) { OmniAI::Chat::Usage.new(input_tokens: 2, output_tokens: 3, total_tokens: 5) }

    it { expect(serialize).to eql(prompt_token_count: 2, candidates_token_count: 3, total_token_count: 5) }
  end
end

# frozen_string_literal: true

RSpec.describe OmniAI::Google::Chat::PayloadSerializer do
  let(:context) { OmniAI::Google::Chat::CONTEXT }

  describe '.serialize' do
    subject(:serialize) { described_class.serialize(payload, context:) }

    let(:payload) { OmniAI::Chat::Payload.new(choices:, usage:) }
    let(:choices) { [OmniAI::Chat::Choice.new(message:)] }
    let(:message) { OmniAI::Chat::Message.new(role: 'user', content: 'Greetings!') }
    let(:usage) { OmniAI::Chat::Usage.new(input_tokens: 2, output_tokens: 3, total_tokens: 5) }

    let(:data) do
      {
        candidates: [
          {
            content: {
              role: 'user',
              parts: [{ text: 'Greetings!' }],
            },
          },
        ],
        usage_metadata: { prompt_token_count: 2, candidates_token_count: 3, total_token_count: 5 },
      }
    end

    it { is_expected.to eql(data) }
  end

  describe '.deserialize' do
    subject(:deserialize) { described_class.deserialize(data, context:) }

    let(:data) do
      {
        'candidates' => [
          {
            'content' => {
              'role' => 'USER',
              'parts' => [{ 'text' => 'Greetings!' }],
            },
          },
        ],
        'usage_metadata' => { 'prompt_token_count' => 2, 'candidates_token_count' => 3, 'total_token_count' => 5 },
      }
    end

    it { is_expected.to be_a(OmniAI::Chat::Payload) }
  end
end
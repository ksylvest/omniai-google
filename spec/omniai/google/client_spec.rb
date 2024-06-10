# frozen_string_literal: true

RSpec.describe OmniAI::Google::Client do
  subject(:client) { described_class.new }

  describe '#chat' do
    it 'proxies' do
      allow(OmniAI::Google::Chat).to receive(:process!)
      client.chat('Hello!')
      expect(OmniAI::Google::Chat).to have_received(:process!)
    end
  end

  describe '#connection' do
    it { expect(client.connection).to be_a(HTTP::Client) }
  end
end

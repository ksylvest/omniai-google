# frozen_string_literal: true

RSpec.describe OmniAI::Google::Chat::MediaSerializer do
  let(:context) { OmniAI::Google::Chat::CONTEXT }

  describe '.serialize' do
    subject(:serialize) { described_class.serialize(media, context:) }

    let(:media) { OmniAI::Chat::File.new(StringIO.new(''), 'text/plain') }

    it { is_expected.to eql(inlineData: { data: '', mimeType: 'text/plain' }) }
  end
end

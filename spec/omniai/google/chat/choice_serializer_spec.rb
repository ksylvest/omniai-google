# frozen_string_literal: true

RSpec.describe OmniAI::Google::Chat::ChoiceSerializer do
  let(:context) { OmniAI::Google::Chat::CONTEXT }

  describe ".serialize" do
    subject(:serialize) { described_class.serialize(choice, context:) }

    let(:choice) { OmniAI::Chat::Choice.new(message:) }
    let(:message) { OmniAI::Chat::Message.new(role: "user", content: "Greetings!") }

    it { is_expected.to eql(content: { role: "user", parts: [{ text: "Greetings!" }] }) }
  end

  describe ".deserialize" do
    subject(:deserialize) { described_class.deserialize(data, context:) }

    let(:data) do
      {
        "content" => {
          "role" => "user",
          "parts" => [{ "text" => "Greetings!" }],
        },
      }
    end

    it { is_expected.to be_a(OmniAI::Chat::Choice) }
  end

  describe ".deserialize finish_reason mapping" do
    subject(:finish_reason) { described_class.deserialize(data, context:).finish_reason }

    let(:data) do
      {
        "content" => { "role" => "model", "parts" => [{ "text" => "Hello!" }] },
        "finishReason" => raw,
      }
    end

    {
      "STOP" => :stop,
      "MAX_TOKENS" => :length,
      "SAFETY" => :filter,
      "RECITATION" => :filter,
      "LANGUAGE" => :filter,
      "BLOCKLIST" => :filter,
      "PROHIBITED_CONTENT" => :filter,
      "SPII" => :filter,
      "IMAGE_SAFETY" => :filter,
      "OTHER" => :other,
      "MALFORMED_FUNCTION_CALL" => :other,
      "SOMETHING_NEW" => :other,
    }.each do |raw, expected|
      context "when finishReason is #{raw.inspect}" do
        let(:raw) { raw }

        it "normalizes the reason" do
          expect(finish_reason.reason).to eq(expected)
        end

        it "preserves the verbatim value" do
          expect(finish_reason.value).to eq(raw)
        end
      end
    end

    context "when finishReason is absent" do
      let(:data) { { "content" => { "role" => "model", "parts" => [{ "text" => "Hello!" }] } } }

      it { is_expected.to be_nil }
    end
  end
end

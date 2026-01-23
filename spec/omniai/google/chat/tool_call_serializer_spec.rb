# frozen_string_literal: true

RSpec.describe OmniAI::Google::Chat::ToolCallSerializer do
  let(:context) { OmniAI::Google::Chat::CONTEXT }

  describe ".deserialize" do
    subject(:deserialize) { described_class.deserialize(data, context:) }

    let(:data) do
      {
        "functionCall" => {
          "name" => "temperature",
          "args" => { "unit" => "celsius" },
        },
      }
    end

    it { expect(deserialize).to be_a(OmniAI::Chat::ToolCall) }

    context "without thoughtSignature" do
      it "has empty options" do
        expect(deserialize.options).to eq({})
      end
    end

    context "with thoughtSignature" do
      let(:data) do
        {
          "functionCall" => {
            "name" => "temperature",
            "args" => { "unit" => "celsius" },
          },
          "thoughtSignature" => "abc123encrypted",
        }
      end

      it "captures thought_signature in options" do
        expect(deserialize.options[:thought_signature]).to eq("abc123encrypted")
      end
    end
  end

  describe ".serialize" do
    subject(:serialize) { described_class.serialize(tool_call, context:) }

    let(:tool_call) { OmniAI::Chat::ToolCall.new(id: "temperature", function:) }
    let(:function) { OmniAI::Google::Chat::Function.new(name: "temperature", arguments: { unit: "celsius" }) }

    it { expect(serialize).to eql(functionCall: { name: "temperature", args: { unit: "celsius" } }) }

    context "with thought_signature option" do
      let(:tool_call) { OmniAI::Chat::ToolCall.new(id: "temperature", function:, thought_signature: "abc123encrypted") }

      it "includes thoughtSignature" do
        expect(serialize).to eql(
          functionCall: { name: "temperature", args: { unit: "celsius" } },
          thoughtSignature: "abc123encrypted"
        )
      end
    end
  end
end

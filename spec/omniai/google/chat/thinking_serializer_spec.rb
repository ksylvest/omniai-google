# frozen_string_literal: true

RSpec.describe OmniAI::Google::Chat::ThinkingSerializer do
  describe ".deserialize" do
    it "extracts thinking from text field" do
      data = { "thought" => true, "text" => "my reasoning" }
      thinking = described_class.deserialize(data)

      expect(thinking.thinking).to eq("my reasoning")
    end

    it "handles nil text" do
      data = { "thought" => true, "text" => nil }
      thinking = described_class.deserialize(data)

      expect(thinking.thinking).to be_nil
    end

    it "initializes metadata as empty hash" do
      data = { "thought" => true, "text" => "reasoning" }
      thinking = described_class.deserialize(data)

      expect(thinking.metadata).to eq({})
    end
  end

  describe ".serialize" do
    it "returns hash with thought flag and text" do
      thinking = OmniAI::Chat::Thinking.new("reasoning")
      result = described_class.serialize(thinking)

      expect(result).to eq({ thought: true, text: "reasoning" })
    end

    it "handles nil thinking content" do
      thinking = OmniAI::Chat::Thinking.new(nil)
      result = described_class.serialize(thinking)

      expect(result).to eq({ thought: true, text: nil })
    end

    it "always sets thought to true" do
      thinking = OmniAI::Chat::Thinking.new("test")
      result = described_class.serialize(thinking)

      expect(result[:thought]).to be true
    end
  end
end

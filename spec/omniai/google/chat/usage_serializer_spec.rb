# frozen_string_literal: true

RSpec.describe OmniAI::Google::Chat::UsageSerializer do
  let(:context) { OmniAI::Google::Chat::CONTEXT }

  describe ".deserialize" do
    subject(:deserialize) { described_class.deserialize(data, context:) }

    context "without thinking" do
      let(:data) do
        {
          "promptTokenCount" => 2,
          "candidatesTokenCount" => 3,
          "totalTokenCount" => 5,
        }
      end

      it { expect(deserialize).to be_a(OmniAI::Chat::Usage) }
      it { expect(deserialize.input_tokens).to be(2) }
      it { expect(deserialize.output_tokens).to be(3) }
      it { expect(deserialize.total_tokens).to be(5) }

      it "leaves thinking_tokens nil rather than reporting zero" do
        expect(deserialize.thinking_tokens).to be_nil
      end
    end

    context "with thinking" do
      # Captured from a live Vertex `generateContent` call: gemini-2.5-flash, us-central1, thinkingBudget 1024.
      let(:data) do
        {
          "promptTokenCount" => 53,
          "candidatesTokenCount" => 550,
          "thoughtsTokenCount" => 806,
          "totalTokenCount" => 1409,
          "trafficType" => "ON_DEMAND",
        }
      end

      it "reports billable output as candidates + thoughts" do
        expect(deserialize.output_tokens).to be(1356)
      end

      it "exposes the reasoning breakdown" do
        expect(deserialize.thinking_tokens).to be(806)
      end

      it "keeps thinking_tokens a subset of output_tokens" do
        expect(deserialize.thinking_tokens).to be <= deserialize.output_tokens
      end

      it "satisfies input + output == total, which candidates-only output did not" do
        expect(deserialize.input_tokens + deserialize.output_tokens).to eq(deserialize.total_tokens)
      end
    end

    context "with a thinking model that reported no thoughts" do
      let(:data) do
        {
          "promptTokenCount" => 2,
          "candidatesTokenCount" => 3,
          "thoughtsTokenCount" => 0,
          "totalTokenCount" => 5,
        }
      end

      it "distinguishes a reported zero from an absent breakdown" do
        expect(deserialize.thinking_tokens).to be(0)
      end

      it { expect(deserialize.output_tokens).to be(3) }
    end

    context "without any token counts" do
      # A truncated stream assembles a usageMetadata carrying only `trafficType`.
      let(:data) { { "trafficType" => "ON_DEMAND" } }

      it "reports no output rather than zero output" do
        expect(deserialize.output_tokens).to be_nil
      end
    end
  end

  describe ".serialize" do
    subject(:serialize) { described_class.serialize(usage, context:) }

    context "without thinking" do
      let(:usage) { OmniAI::Chat::Usage.new(input_tokens: 2, output_tokens: 3, total_tokens: 5) }

      it "omits thoughtsTokenCount entirely, as Gemini does" do
        expect(serialize).to eql(promptTokenCount: 2, candidatesTokenCount: 3, totalTokenCount: 5)
      end
    end

    context "with thinking" do
      let(:usage) do
        OmniAI::Chat::Usage.new(input_tokens: 53, output_tokens: 1356, total_tokens: 1409, thinking_tokens: 806)
      end

      it "splits inclusive output back into candidates and thoughts" do
        expect(serialize).to eql(
          promptTokenCount: 53,
          candidatesTokenCount: 550,
          totalTokenCount: 1409,
          thoughtsTokenCount: 806
        )
      end

      it "round-trips" do
        usage = described_class.deserialize(serialize.transform_keys(&:to_s), context:)
        expect(usage.output_tokens).to be(1356)
        expect(usage.thinking_tokens).to be(806)
      end
    end
  end
end

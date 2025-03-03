# frozen_string_literal: true

RSpec.describe OmniAI::Google::Chat::Stream do
  subject(:stream) { described_class.new(chunks:) }

  describe ".stream!" do
    subject(:stream!) { stream.stream! { |delta| deltas << delta } }

    let(:deltas) { [] }

    context "when parsing text chunks" do
      let(:chunks) do
        [
          {
            candidates: [
              {
                content: {
                  role: "model",
                  parts: [{
                    text: "Hello",
                  }],
                },
              },
            ],
          },
          {
            candidates: [
              {
                content: {
                  role: "model",
                  parts: [{ text: " " }],
                },
              },
            ],
          },
          {
            candidates: [
              {
                content: {
                  role: "model",
                  parts: [{ text: "World" }],
                },
              },
            ],
          },
        ].map { |chunk| "data: #{JSON.generate(chunk)}\n\n" }
      end

      it "combines multiple chunks" do
        expect(stream!).to eql({
          "candidates" => [
            {
              "content" => {
                "role" => "model",
                "parts" => [
                  {
                    "text" => "Hello World",
                  },
                ],
              },
            },
          ],
        })
      end

      it "yields multiple times" do
        stream!
        expect(deltas.filter(&:text?).map(&:text)).to eql([
          "Hello",
          " ",
          "World",
        ])
      end
    end

    context "when parsing tool call list chunks" do
      let(:chunks) do
        [
          {
            candidates: [
              {
                content: {
                  role: "model",
                  parts: [
                    {
                      functionCall: { name: "weather", arguments: JSON.generate(location: "Madrid") },
                    },
                    {
                      functionCall: { name: "weather", arguments: JSON.generate(location: "London") },
                    },
                    {
                      functionCall: { name: "weather", arguments: JSON.generate(location: "Berlin") },
                    },
                  ],
                },
              },
            ],
          },
        ].map { |chunk| "data: #{JSON.generate(chunk)}\n\n" }
      end

      it "combines multiple chunks" do
        expect(stream!).to eql({
          "candidates" => [
            {
              "content" => {
                "role" => "model",
                "parts" => [
                  {
                    "functionCall" => {
                      "name" => "weather",
                      "arguments" => JSON.generate(location: "Madrid"),
                    },
                  },
                  {
                    "functionCall" => {
                      "name" => "weather",
                      "arguments" => JSON.generate(location: "London"),
                    },
                  },
                  {
                    "functionCall" => {
                      "name" => "weather",
                      "arguments" => JSON.generate(location: "Berlin"),
                    },
                  },
                ],
              },
            },
          ],
        })
      end

      it "does not yield" do
        stream!
        expect(deltas).to eql([])
      end
    end
  end
end

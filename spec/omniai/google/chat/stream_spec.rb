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
                  parts: [{ text: "Hello" }],
                },
                index: 0,
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
                index: 0,
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
                index: 0,
              },
            ],
          },
          {
            candidates: [{ finishReason: "STOP", index: 0 }],
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
              "index" => 0,
              "finishReason" => "STOP",
            },
          ],
        })
      end

      it "yields multiple times" do
        stream!
        expect(deltas.map(&:text)).to eql([
          "Hello",
          " ",
          "World",
        ])
      end
    end

    context "when parsing thought chunks followed by text chunks" do
      let(:chunks) do
        [
          {
            candidates: [
              {
                content: {
                  role: "model",
                  parts: [{ text: "Let me ", thought: true }],
                },
                index: 0,
              },
            ],
          },
          {
            candidates: [
              {
                content: {
                  role: "model",
                  parts: [{ text: "think.", thought: true }],
                },
                index: 0,
              },
            ],
          },
          {
            candidates: [
              {
                content: {
                  role: "model",
                  parts: [{ text: "The answer " }],
                },
                index: 0,
              },
            ],
          },
          {
            candidates: [
              {
                content: {
                  role: "model",
                  parts: [{ text: "is 42." }],
                },
                index: 0,
              },
            ],
          },
          {
            candidates: [{ finishReason: "STOP", index: 0 }],
          },
        ].map { |chunk| "data: #{JSON.generate(chunk)}\n\n" }
      end

      it "keeps thought and answer parts separate so response.text is not absorbed into the thought" do
        expect(stream!).to eql({
          "candidates" => [
            {
              "content" => {
                "role" => "model",
                "parts" => [
                  { "text" => "Let me think.", "thought" => true },
                  { "text" => "The answer is 42." },
                ],
              },
              "index" => 0,
              "finishReason" => "STOP",
            },
          ],
        })
      end

      it "yields thinking deltas and text deltas separately" do
        stream!
        expect(deltas.map { |d| [d.text, d.thinking] }).to eql([
          [nil, "Let me "],
          [nil, "think."],
          ["The answer ", nil],
          ["is 42.", nil],
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
                  ],
                },
                index: 0,
              },
            ],
          },
          {
            candidates: [
              {
                content: {
                  role: "model",
                  parts: [
                    {
                      functionCall: { name: "weather", arguments: JSON.generate(location: "London") },
                    },
                  ],
                },
                index: 0,
              },
            ],
          },
          {
            candidates: [
              {
                content: {
                  role: "model",
                  parts: [
                    {
                      functionCall: { name: "weather", arguments: JSON.generate(location: "Berlin") },
                    },
                  ],
                },
                index: 0,
              },
            ],
          },
          {
            candidates: [{ finishReason: "STOP", index: 0 }],
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
              "index" => 0,
              "finishReason" => "STOP",
            },
          ],
        })
      end

      it "does not yield" do
        stream!
        expect(deltas).to eql([])
      end
    end

    context "when a candidate has content without parts followed by content with parts" do
      let(:chunks) do
        [
          {
            candidates: [
              {
                content: {},
                finishReason: "STOP",
              },
            ],
          },
          {
            candidates: [
              {
                content: {
                  role: "model",
                  parts: [{ text: "Hello" }],
                },
                index: 0,
              },
            ],
          },
        ].map { |chunk| "data: #{JSON.generate(chunk)}\n\n" }
      end

      it "merges correctly" do
        expect(stream!).to eql({
          "candidates" => [
            {
              "content" => {
                "parts" => [
                  { "text" => "Hello" },
                ],
              },
              "finishReason" => "STOP",
              "index" => 0,
            },
          ],
        })
      end

      it "yields only for chunks with parts" do
        stream!
        expect(deltas.map(&:text)).to eql(["Hello"])
      end
    end

    context "when a candidate has content without parts" do
      let(:chunks) do
        [
          {
            candidates: [
              {
                content: {
                  role: "model",
                  parts: [{ text: "Hello" }],
                },
                index: 0,
              },
            ],
          },
          {
            candidates: [
              {
                content: {},
                finishReason: "STOP",
              },
            ],
          },
        ].map { |chunk| "data: #{JSON.generate(chunk)}\n\n" }
      end

      it "merges correctly" do
        expect(stream!).to eql({
          "candidates" => [
            {
              "content" => {
                "role" => "model",
                "parts" => [
                  { "text" => "Hello" },
                ],
              },
              "index" => 0,
              "finishReason" => "STOP",
            },
          ],
        })
      end

      it "yields only for chunks with parts" do
        stream!
        expect(deltas.map(&:text)).to eql(["Hello"])
      end
    end

    context "when finishReason arrives on a terminal chunk with no content (the real Gemini ordering)" do
      let(:chunks) do
        [
          {
            candidates: [
              { content: { role: "model", parts: [{ text: "Hello" }] }, index: 0 },
            ],
          },
          {
            candidates: [
              { content: { role: "model", parts: [{ text: " World" }] }, index: 0 },
            ],
          },
          {
            candidates: [
              { finishReason: "MAX_TOKENS", index: 0 },
            ],
          },
        ].map { |chunk| "data: #{JSON.generate(chunk)}\n\n" }
      end

      it "preserves finishReason on the assembled candidate" do
        expect(stream!).to eql({
          "candidates" => [
            {
              "content" => {
                "role" => "model",
                "parts" => [
                  { "text" => "Hello World" },
                ],
              },
              "index" => 0,
              "finishReason" => "MAX_TOKENS",
            },
          ],
        })
      end

      it "yields each text chunk" do
        stream!
        expect(deltas.map(&:text)).to eql(["Hello", " World"])
      end
    end

    context "when parsing function-call chunks followed by text chunks" do
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
                  ],
                },
                index: 0,
              },
            ],
          },
          {
            candidates: [
              {
                content: {
                  role: "model",
                  parts: [{ text: "It's " }],
                },
                index: 0,
              },
            ],
          },
          {
            candidates: [
              {
                content: {
                  role: "model",
                  parts: [{ text: "sunny." }],
                },
                index: 0,
              },
            ],
          },
          {
            candidates: [{ finishReason: "STOP", index: 0 }],
          },
        ].map { |chunk| "data: #{JSON.generate(chunk)}\n\n" }
      end

      it "keeps the function-call and text parts separate" do
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
                  { "text" => "It's sunny." },
                ],
              },
              "index" => 0,
              "finishReason" => "STOP",
            },
          ],
        })
      end

      it "yields text deltas only (no delta for the function-call)" do
        stream!
        expect(deltas.map(&:text)).to eql(["It's ", "sunny."])
      end
    end

    context "when parsing text and tool call list chunks" do
      let(:chunks) do
        [
          {
            candidates: [
              {
                content: {
                  role: "model",
                  parts: [{ text: "Hello" }],
                },
                index: 0,
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
                index: 0,
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
                index: 0,
              },
            ],
          },
          {
            candidates: [
              {
                content: {
                  role: "model",
                  parts: [
                    {
                      functionCall: { name: "weather", arguments: JSON.generate(location: "Madrid") },
                    },
                  ],
                },
                index: 0,
              },
            ],
          },
          {
            candidates: [
              {
                content: {
                  role: "model",
                  parts: [
                    {
                      functionCall: { name: "weather", arguments: JSON.generate(location: "London") },
                    },
                  ],
                },
                index: 0,
              },
            ],
          },
          {
            candidates: [
              {
                content: {
                  role: "model",
                  parts: [
                    {
                      functionCall: { name: "weather", arguments: JSON.generate(location: "Berlin") },
                    },
                  ],
                },
                index: 0,
              },
            ],
          },
          {
            candidates: [{ finishReason: "STOP", index: 0 }],
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
              "index" => 0,
              "finishReason" => "STOP",
            },
          ],
        })
      end

      it "yields multiple times" do
        stream!
        expect(deltas.map(&:text)).to eql([
          "Hello",
          " ",
          "World",
        ])
      end
    end

    context "when the stream ends without a finish reason" do
      let(:chunks) do
        [
          {
            candidates: [
              { content: { role: "model", parts: [{ text: "hmm", thought: true }] }, index: 0 },
            ],
          },
        ].map { |chunk| "data: #{JSON.generate(chunk)}\n\n" }
      end

      # Shape captured in production (Sentry APP-GK, 89 events on 2026-08-20, gemini-3.7-flash):
      # one candidate, one part, thought: true, no finishReason key, no answer text.
      it "raises rather than returning the fragment as an answer" do
        expect { stream! }.to raise_error(OmniAI::Google::IncompleteStreamError)
      end

      it "reports the structure of what did arrive" do
        expect { stream! }.to raise_error(/candidate=0 parts=1 thought_parts=1 finish_reason=nil/)
      end

      it "keeps part text out of the message" do
        expect { stream! }.to(raise_error { |error| expect(error.message).not_to include("hmm") })
      end

      it "carries no response, so callers retry it" do
        expect { stream! }.to raise_error(OmniAI::Error) { |error|
          expect(error).not_to respond_to(:response)
        }
      end
    end

    context "when the stream carries no candidates at all" do
      let(:chunks) { ["data: #{JSON.generate({ usageMetadata: { promptTokenCount: 7 } })}\n\n"] }

      it "raises rather than returning an empty success" do
        expect { stream! }.to raise_error(OmniAI::Google::IncompleteStreamError, /candidates=0/)
      end
    end

    context "when the stream carries an error object after the 200" do
      let(:chunks) do
        [
          { candidates: [{ content: { role: "model", parts: [{ text: "par", thought: true }] }, index: 0 }] },
          { error: { code: 503, status: "UNAVAILABLE", message: "overloaded" } },
        ].map { |chunk| "data: #{JSON.generate(chunk)}\n\n" }
      end

      it "raises instead of swallowing it into the aggregate" do
        expect { stream! }.to raise_error(OmniAI::Google::StreamError)
      end

      it "exposes Google's message on #provider_message, off the exception message" do
        expect { stream! }.to(raise_error { |error| expect(error.provider_message).to eql("overloaded") })
      end

      it "surfaces Google's code and status, but not its message" do
        # The message can echo request content back and consumers log these.
        expect { stream! }.to raise_error(/code=503 status="UNAVAILABLE"/) { |error|
          expect(error.message).not_to include("overloaded")
        }
      end
    end

    context "when the stream finishes for a reason the caller must decide about" do
      let(:chunks) do
        [
          { candidates: [{ content: { role: "model", parts: [{ text: "Otta" }] }, index: 0 }] },
          { candidates: [{ finishReason: "MAX_TOKENS", index: 0 }] },
        ].map { |chunk| "data: #{JSON.generate(chunk)}\n\n" }
      end

      it "does not raise, because the generation reported how it ended" do
        expect { stream! }.not_to raise_error
      end
    end

    context "when the stream ends without a finish reason but delivered an answer" do
      let(:chunks) do
        [
          { candidates: [{ content: { role: "model", parts: [{ text: "a complete answer" }] }, index: 0 }] },
        ].map { |chunk| "data: #{JSON.generate(chunk)}\n\n" }
      end

      it "returns it rather than discarding a turn that worked" do
        expect { stream! }.not_to raise_error
      end

      it "leaves finish_reason nil rather than inventing one" do
        response = OmniAI::Chat::Response.deserialize(stream!, context: OmniAI::Google::Chat::CONTEXT)
        expect(response.text).to eql("a complete answer")
        expect(response.choices.first.finish_reason).to be_nil
      end
    end

    context "when the stream ends without a finish reason but made a tool call" do
      let(:chunks) do
        [
          {
            candidates: [
              { content: { role: "model", parts: [{ functionCall: { name: "temperature", args: {} } }] }, index: 0 },
            ],
          },
        ].map { |chunk| "data: #{JSON.generate(chunk)}\n\n" }
      end

      it "returns it, because the generation produced something" do
        expect { stream! }.not_to raise_error
      end
    end

    context "when a safety block comes back as a candidate with no parts" do
      # Captured from Vertex (gemini-3.8-flash, safetySettings BLOCK_LOW_AND_ABOVE): a real
      # block arrives candidate-level with finishReason SAFETY, not as promptFeedback.
      let(:chunks) do
        [{ candidates: [{ content: { role: "model" }, finishReason: "SAFETY", index: 0 }] }]
          .map { |chunk| "data: #{JSON.generate(chunk)}\n\n" }
      end

      it "returns it, because the model reported why it stopped" do
        expect { stream! }.not_to raise_error
      end

      it "keeps the provider's reason" do
        response = OmniAI::Chat::Response.deserialize(stream!, context: OmniAI::Google::Chat::CONTEXT)
        expect(response.choices.first.finish_reason.value).to eql("SAFETY")
      end
    end

    context "when the only answer part is an empty string" do
      let(:chunks) do
        [{ candidates: [{ content: { role: "model", parts: [{ text: "" }] }, index: 0 }] }]
          .map { |chunk| "data: #{JSON.generate(chunk)}\n\n" }
      end

      it "raises, since an empty string is not an answer" do
        expect { stream! }.to raise_error(OmniAI::Google::IncompleteStreamError)
      end
    end
  end
end

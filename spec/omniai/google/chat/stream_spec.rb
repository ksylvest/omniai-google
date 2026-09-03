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
          # A real Gemini stream ends with a terminal chunk carrying the finish reason.
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
          # A real Gemini stream ends with a terminal chunk carrying the finish reason.
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
          # A real Gemini stream ends with a terminal chunk carrying the finish reason.
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
          # A real Gemini stream ends with a terminal chunk carrying the finish reason.
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
          # A real Gemini stream ends with a terminal chunk carrying the finish reason.
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

      it "raises rather than returning the fragment as an answer" do
        # Observed in production: 129 events in an hour, every part thought-only, no
        # finishReason. Before this the caller got an empty, successful response.
        expect { stream! }.to raise_error(OmniAI::Google::IncompleteStreamError)
      end

      it "reports the structure of what did arrive" do
        expect { stream! }.to raise_error(/candidate=0 parts=1 thought_parts=1 finish_reason=nil/)
      end

      it "does not put part text in the message, which may be PHI" do
        expect { stream! }.to(raise_error { |error| expect(error.message).not_to include("hmm") })
      end

      it "is an OmniAI::Error that carries no response, so callers retry it" do
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
        # process_data! copies every non-candidate key into @data, so this landed in
        # @data["error"] and the caller received an empty SUCCESSFUL response for an outage.
        expect { stream! }.to raise_error(OmniAI::Google::StreamError)
      end

      it "surfaces Google's code, status and message" do
        expect { stream! }
          .to raise_error(/code=503 status="UNAVAILABLE" message="overloaded"/)
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
        # SAFETY and MAX_TOKENS are answers about the generation, not failures of the stream.
        expect { stream! }.not_to raise_error
      end
    end
  end
end

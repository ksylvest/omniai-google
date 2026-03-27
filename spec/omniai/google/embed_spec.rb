# frozen_string_literal: true

RSpec.describe OmniAI::Google::Embed do
  let(:client) { OmniAI::Google::Client.new }
  let(:project_id) { "fake" }

  describe ".process!" do
    subject(:process!) { described_class.process!(text, client:, model:) }

    let(:text) { "The quick brown fox jumps over a lazy dog." }
    let(:model) { described_class::DEFAULT_MODEL }
    let(:location) { OmniAI::Google::Config::DEFAULT_LOCATION }

    before do
      stub_request(:post, "https://generativelanguage.googleapis.com//v1beta/models/#{model}:batchEmbedContents?key=...")
        .with(body: {
          requests: [
            {
              model: "models/#{model}",
              content: { parts: [{ text: text }] },
            },
          ],
        })
        .to_return_json(body: { embeddings: [{ values: [0.0] }] })
    end

    it { expect(process!).to be_a(OmniAI::Embed::Response) }
    it { expect(process!.embedding).to eql([0.0]) }

    context "with gemini-embedding-001" do
      let(:model) { described_class::Model::GEMINI_EMBEDDING_001 }

      it { expect(process!).to be_a(OmniAI::Embed::Response) }
      it { expect(process!.embedding).to eql([0.0]) }
    end

    context "with gemini-embedding-2-preview" do
      let(:model) { described_class::Model::GEMINI_EMBEDDING_2_PREVIEW }

      it { expect(process!).to be_a(OmniAI::Embed::Response) }
      it { expect(process!.embedding).to eql([0.0]) }
    end

    context "with text-embedding-005" do
      let(:model) { described_class::Model::TEXT_EMBEDDING_005 }

      it { expect(process!).to be_a(OmniAI::Embed::Response) }
      it { expect(process!.embedding).to eql([0.0]) }
    end

    context "with batch input (batchEmbedContents)" do
      subject(:process!) { described_class.process!(texts, client:, model:) }

      let(:texts) { ["Hello", "World"] }

      before do
        stub_request(:post, "https://generativelanguage.googleapis.com//v1beta/models/#{model}:batchEmbedContents?key=...")
          .with(body: {
            requests: [
              { model: "models/#{model}", content: { parts: [{ text: "Hello" }] } },
              { model: "models/#{model}", content: { parts: [{ text: "World" }] } },
            ],
          })
          .to_return_json(body: { embeddings: [{ values: [0.1] }, { values: [0.2] }] })
      end

      it { expect(process!.embeddings).to eql([[0.1], [0.2]]) }
    end

    context "without task_type (batchEmbedContents)" do
      it "does not include taskType in the payload" do
        embed = described_class.new(text, client: client, model: model)
        payload = embed.send(:batch_embed_contents_payload)
        expect(payload[:requests].first).not_to have_key(:taskType)
      end
    end

    context "with task_type (batchEmbedContents)" do
      subject(:process!) { described_class.process!(text, client:, model:, task_type: "RETRIEVAL_DOCUMENT") }

      before do
        stub_request(:post, "https://generativelanguage.googleapis.com//v1beta/models/#{model}:batchEmbedContents?key=...")
          .with(body: {
            requests: [
              {
                model: "models/#{model}",
                content: { parts: [{ text: text }] },
                taskType: "RETRIEVAL_DOCUMENT",
              },
            ],
          })
          .to_return_json(body: { embeddings: [{ values: [0.0] }] })
      end

      it { expect(process!).to be_a(OmniAI::Embed::Response) }
      it { expect(process!.embedding).to eql([0.0]) }
    end

    context "with vertex" do
      let(:client) do
        OmniAI::Google::Client.new(
          credentials: credentials,
          host: "https://us-central1-aiplatform.googleapis.com",
          project_id: "test-project",
          location_id: "us-central1"
        )
      end

      let(:credentials) do
        instance_double(Google::Auth::ServiceAccountCredentials, fetch_access_token!: nil, access_token: "token")
      end

      context "with gemini-embedding-001 (predict)" do
        let(:model) { described_class::Model::GEMINI_EMBEDDING_001 }

        before do
          stub_request(:post, "https://us-central1-aiplatform.googleapis.com//v1beta/projects/test-project/locations/us-central1/publishers/google/models/#{model}:predict")
            .with(body: {
              instances: [{ content: text }],
            })
            .to_return_json(body: { predictions: [{ embeddings: { values: [0.0], statistics: { token_count: 10 } } }] })
        end

        it { expect(process!).to be_a(OmniAI::Embed::Response) }
        it { expect(process!.embedding).to eql([0.0]) }
        it { expect(process!.usage.total_tokens).to eql(10) }
      end

      context "with gemini-embedding-2-preview (embedContent)" do
        let(:model) { described_class::Model::GEMINI_EMBEDDING_2_PREVIEW }

        before do
          stub_request(:post, "https://us-central1-aiplatform.googleapis.com//v1beta/projects/test-project/locations/us-central1/publishers/google/models/#{model}:embedContent")
            .with(body: {
              content: { parts: [{ text: text }] },
            })
            .to_return_json(body: {
              embedding: { values: [0.0] },
              usageMetadata: { promptTokenCount: 5, totalTokenCount: 5 },
            })
        end

        it { expect(process!).to be_a(OmniAI::Embed::Response) }
        it { expect(process!.embedding).to eql([0.0]) }
        it { expect(process!.usage.total_tokens).to eql(5) }
        it { expect(process!.usage.prompt_tokens).to eql(5) }

        context "with task_type" do
          subject(:process!) { described_class.process!(text, client:, model:, task_type: "RETRIEVAL_QUERY") }

          before do
            stub_request(:post, "https://us-central1-aiplatform.googleapis.com//v1beta/projects/test-project/locations/us-central1/publishers/google/models/#{model}:embedContent")
              .with(body: {
                content: { parts: [{ text: text }] },
                taskType: "RETRIEVAL_QUERY",
              })
              .to_return_json(body: {
                embedding: { values: [0.0] },
                usageMetadata: { promptTokenCount: 5, totalTokenCount: 5 },
              })
          end

          it { expect(process!).to be_a(OmniAI::Embed::Response) }
          it { expect(process!.embedding).to eql([0.0]) }
        end

        context "with batch input" do
          let(:text) { ["Hello", "World"] }

          it { expect { process! }.to raise_error(ArgumentError, "embedContent does not support batch input") }
        end
      end
    end
  end
end

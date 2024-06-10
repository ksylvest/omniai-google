# frozen_string_literal: true

RSpec.describe OmniAI::Google::Chat do
  let(:client) { OmniAI::Google::Client.new }

  describe '.process!' do
    subject(:completion) { described_class.process!(prompt, client:, model:) }

    let(:model) { described_class::Model::GEMINI_PRO }

    context 'with a string prompt' do
      let(:prompt) { 'Tell me a joke!' }

      before do
        stub_request(:post, "https://generativelanguage.googleapis.com/v1/models/#{model}:generateContent?key=...")
          .with(body: {
            contents: [
              { role: 'user', parts: [{ text: prompt }] },
            ],
          })
          .to_return_json(body: {
            candidates: [{
              index: 0,
              content: {
                role: 'assistant',
                parts: [{ text: 'Two elephants fall off a cliff. Boom! Boom!' }],
              },
            }],
          })
      end

      it { expect(completion.choice.message.role).to eql('assistant') }
      it { expect(completion.choice.message.content).to eql('Two elephants fall off a cliff. Boom! Boom!') }
    end

    context 'with an array prompt' do
      let(:prompt) do
        [
          { role: OmniAI::Chat::Role::SYSTEM, content: 'You are a helpful assistant.' },
          { role: OmniAI::Chat::Role::USER, content: 'What is the capital of Canada?' },
        ]
      end

      before do
        stub_request(:post, "https://generativelanguage.googleapis.com/v1/models/#{model}:generateContent?key=...")
          .with(body: {
            contents: [
              { role: 'system', parts: [{ text: 'You are a helpful assistant.' }] },
              { role: 'user', parts: [{ text: 'What is the capital of Canada?' }] },

            ],
          })
          .to_return_json(body: {
            candidates: [{
              index: 0,
              content: {
                role: 'assistant',
                parts: [{ text: 'The capital of Canada is Ottawa.' }],
              },
            }],
          })
      end

      it { expect(completion.choice.message.role).to eql('assistant') }
      it { expect(completion.choice.message.content).to eql('The capital of Canada is Ottawa.') }
    end

    context 'with a temperature' do
      subject(:completion) { described_class.process!(prompt, client:, model:, temperature:) }

      let(:prompt) { 'Pick a number between 1 and 5.' }
      let(:temperature) { 2.0 }

      before do
        stub_request(:post, "https://generativelanguage.googleapis.com/v1/models/#{model}:generateContent?key=...")
          .with(body: {
            generationConfig: { temperature: },
            contents: [
              { role: 'user', parts: [{ text: prompt }] },
            ],
          })
          .to_return_json(body: {
            candidates: [{
              index: 0,
              content: {
                role: 'assistant',
                parts: [{ text: '3' }],
              },
            }],
          })
      end

      it { expect(completion.choice.message.role).to eql('assistant') }
      it { expect(completion.choice.message.content).to eql('3') }
    end

    context 'when streaming' do
      subject(:completion) { described_class.process!(prompt, client:, model:, stream:) }

      let(:prompt) { 'Tell me a story.' }
      let(:stream) { proc { |chunk| } }

      before do
        stub_request(:post, "https://generativelanguage.googleapis.com/v1/models/#{model}:streamGenerateContent?alt=sse&key=...")
          .with(body: {
            contents: [
              { role: 'user', parts: [{ text: prompt }] },
            ],
          })
          .to_return(body: <<~STREAM)
            data: #{JSON.generate(candidates: [{ content: { parts: [{ text: 'A' }], role: 'model' }, index: 0 }])}\n
            data: #{JSON.generate(candidates: [{ content: { parts: [{ text: 'B' }], role: 'model' }, index: 0 }])}\n
          STREAM
      end

      it do
        chunks = []
        allow(stream).to receive(:call) { |chunk| chunks << chunk }
        completion
        expect(chunks.map { |chunk| chunk.choice.delta.content }).to eql(%w[A B])
      end
    end
  end
end

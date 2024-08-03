# frozen_string_literal: true

module OmniAI
  module Google
    # An Google embed implementation.
    #
    # Usage:
    #
    #   input = "..."
    #   response = OmniAI::Google::Embed.process!(input, client: client)
    #   response.embedding [0.0, ...]
    class Embed < OmniAI::Embed
      module Model
        EMBEDDING_4 = 'text-embedding-004'
        MULTILINGUAL_EMBEDDING_2 = 'text-multilingual-embedding-002'
        EMBEDDING = EMBEDDING_4
        MULTILINGUAL_EMBEDDING = MULTILINGUAL_EMBEDDING_2
      end

      DEFAULT_MODEL = Model::EMBEDDING

      EMBEDDINGS_DESERIALIZER = proc do |data, *|
        data['predictions'].map { |embedding| embedding['embeddings']['values'] }
      end

      USAGE_DESERIALIZER = proc do |data, *|
        token_count = data['predictions'].sum { |prediction| prediction['embeddings']['statistics']['token_count'] }
        Usage.new(prompt_tokens: token_count, total_tokens: token_count)
      end

      # @return [Context]
      CONTEXT = Context.build do |context|
        context.deserializers[:usage] = USAGE_DESERIALIZER
        context.deserializers[:embeddings] = EMBEDDINGS_DESERIALIZER
      end

      protected

      # @param response [HTTP::Response]
      # @return [Response]
      def parse!(response:)
        Response.new(data: response.parse, context: CONTEXT)
      end

      # @return [Hash]
      def payload
        { instances: @input.is_a?(Array) ? @input.map { |content| { content: } } : [{ content: @input }] }
      end

      # @return [String]
      def path
        "/#{@client.path}/models/#{@model}:predict"
      end
    end
  end
end

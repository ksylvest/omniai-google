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
        TEXT_EMBEDDING_004 = "text-embedding-004"
        TEXT_MULTILINGUAL_EMBEDDING_002 = "text-multilingual-embedding-002"
        EMBEDDING = TEXT_EMBEDDING_004
        MULTILINGUAL_EMBEDDING = TEXT_MULTILINGUAL_EMBEDDING_002
      end

      DEFAULT_MODEL = Model::EMBEDDING

      EMBEDDINGS_DESERIALIZER = proc do |data, *|
        data["embeddings"].map { |embedding| embedding["values"] }
      end

      # @return [Context]
      CONTEXT = Context.build do |context|
        context.deserializers[:embeddings] = EMBEDDINGS_DESERIALIZER
      end

    protected

      # @param response [HTTP::Response]
      # @return [Response]
      def parse!(response:)
        Response.new(data: response.parse, context: CONTEXT)
      end

      # @return [Array<Hash<{ text: String }>]
      def requests
        arrayify(@input).map do |text|
          {
            model: "models/#{@model}",
            content: { parts: [{ text: }] },
          }
        end
      end

      # @return [Hash]
      def payload
        { requests: }
      end

      # @return [String]
      def path
        "/#{@client.path}/models/#{@model}:batchEmbedContents?key=#{@client.api_key}"
      end

      def arrayify(input)
        input.is_a?(Array) ? input : [input]
      end
    end
  end
end

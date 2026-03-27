# frozen_string_literal: true

module OmniAI
  module Google
    # A Google embed implementation.
    #
    # Usage:
    #
    #   input = "..."
    #   response = OmniAI::Google::Embed.process!(input, client: client)
    #   response.embedding [0.0, ...]
    class Embed < OmniAI::Embed
      module Model
        TEXT_EMBEDDING_004 = "text-embedding-004"
        TEXT_EMBEDDING_005 = "text-embedding-005"
        TEXT_MULTILINGUAL_EMBEDDING_002 = "text-multilingual-embedding-002"
        GEMINI_EMBEDDING_001 = "gemini-embedding-001"
        GEMINI_EMBEDDING_2_PREVIEW = "gemini-embedding-2-preview"
        EMBEDDING = TEXT_EMBEDDING_004
        MULTILINGUAL_EMBEDDING = TEXT_MULTILINGUAL_EMBEDDING_002
      end

      DEFAULT_MODEL = Model::EMBEDDING

      BATCH_EMBED_CONTENTS_DESERIALIZER = proc do |data, *|
        data["embeddings"].map { |embedding| embedding["values"] }
      end

      PREDICT_EMBEDDINGS_DESERIALIZER = proc do |data, *|
        data["predictions"].map { |prediction| prediction["embeddings"]["values"] }
      end

      PREDICT_USAGE_DESERIALIZER = proc do |data, *|
        tokens = data["predictions"].sum { |prediction| prediction["embeddings"]["statistics"]["token_count"] }

        Usage.new(prompt_tokens: tokens, total_tokens: tokens)
      end

      EMBED_CONTENT_DESERIALIZER = proc do |data, *|
        [data["embedding"]["values"]]
      end

      USAGE_METADATA_DESERIALIZER = proc do |data, *|
        prompt_tokens = data.dig("usageMetadata", "promptTokenCount")
        total_tokens = data.dig("usageMetadata", "totalTokenCount")

        Usage.new(prompt_tokens: prompt_tokens, total_tokens: total_tokens)
      end

      # @return [Context]
      BATCH_EMBED_CONTENTS_CONTEXT = Context.build do |context|
        context.deserializers[:embeddings] = BATCH_EMBED_CONTENTS_DESERIALIZER
        context.deserializers[:usage] = USAGE_METADATA_DESERIALIZER
      end

      # @return [Context]
      PREDICT_CONTEXT = Context.build do |context|
        context.deserializers[:embeddings] = PREDICT_EMBEDDINGS_DESERIALIZER
        context.deserializers[:usage] = PREDICT_USAGE_DESERIALIZER
      end

      # @return [Context]
      EMBED_CONTENT_CONTEXT = Context.build do |context|
        context.deserializers[:embeddings] = EMBED_CONTENT_DESERIALIZER
        context.deserializers[:usage] = USAGE_METADATA_DESERIALIZER
      end

    protected

      # Determines which endpoint to use based on client and model configuration.
      # Routes gemini-embedding-2-* models to embedContent on Vertex, as Google's
      # Vertex AI requires this endpoint for newer multimodal embedding models.
      #
      # @return [Symbol] :embed_content, :predict, or :batch_embed_contents
      def endpoint
        @endpoint ||= if @client.vertex? && @model.start_with?("gemini-embedding-2")
          :embed_content
        elsif @client.vertex?
          :predict
        else
          :batch_embed_contents
        end
      end

      # @return [Context]
      def context
        case endpoint
        when :embed_content then EMBED_CONTENT_CONTEXT
        when :predict then PREDICT_CONTEXT
        when :batch_embed_contents then BATCH_EMBED_CONTENTS_CONTEXT
        end
      end

      # @return [Hash]
      def payload
        case endpoint
        when :embed_content then embed_content_payload
        when :predict then predict_payload
        when :batch_embed_contents then batch_embed_contents_payload
        end
      end

      # Builds payload for the Vertex embedContent endpoint (gemini-embedding-2-* models).
      # @return [Hash]
      def embed_content_payload
        raise ArgumentError, "embedContent does not support batch input" if @input.is_a?(Array) && @input.length > 1

        text = @input.is_a?(Array) ? @input.first : @input
        result = { content: { parts: [{ text: text }] } }
        result[:taskType] = @options[:task_type] if @options[:task_type]
        result
      end

      # Builds payload for the Vertex predict endpoint (text-embedding and gemini-embedding-001 models).
      # @return [Hash]
      def predict_payload
        inputs = arrayify(@input)
        { instances: inputs.map { |text| { content: text } } }
      end

      # Builds payload for the Google AI batchEmbedContents endpoint (non-Vertex).
      # @return [Hash]
      def batch_embed_contents_payload
        inputs = arrayify(@input)
        {
          requests: inputs.map do |text|
            request = {
              model: "models/#{@model}",
              content: { parts: [{ text: text }] },
            }
            request[:taskType] = @options[:task_type] if @options[:task_type]
            request
          end
        }
      end

      # @return [Hash]
      def params
        { key: (@client.api_key unless @client.credentials?) }.compact
      end

      # @return [String]
      def path
        procedure = case endpoint
                    when :embed_content then "embedContent"
                    when :predict then "predict"
                    when :batch_embed_contents then "batchEmbedContents"
                    end

        "/#{@client.path}/models/#{@model}:#{procedure}"
      end
    end
  end
end

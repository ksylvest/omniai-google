# frozen_string_literal: true

module OmniAI
  module Google
    # Vertex AI endpoints.
    module Vertex
      MULTI_REGIONS = %w[us eu].freeze

      # The host serving a location, derived the way Google's own SDKs do (google-genai, vertexai).
      #
      # @param location_id [String] e.g. "global", "us" or "us-central1"
      #
      # @return [String]
      def self.host(location_id)
        if location_id.eql?("global")
          "https://aiplatform.googleapis.com"
        elsif MULTI_REGIONS.include?(location_id)
          "https://aiplatform.#{location_id}.rep.googleapis.com"
        else
          "https://#{location_id}-aiplatform.googleapis.com"
        end
      end
    end
  end
end

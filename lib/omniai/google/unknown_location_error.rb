# frozen_string_literal: true

module OmniAI
  module Google
    # Raised before any request when `locations` is configured but has no entry for the model.
    class UnknownLocationError < OmniAI::Error
      # @return [String]
      attr_reader :model

      # @param model [String]
      def initialize(model)
        @model = model
        super("no location configured for model #{model.inspect}")
      end
    end
  end
end

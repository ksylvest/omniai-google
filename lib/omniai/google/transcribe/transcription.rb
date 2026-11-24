# frozen_string_literal: true

module OmniAI
  module Google
    class Transcribe
      # A Speech-to-Text (Chirp) transcription, with the details Google reports for billing.
      class Transcription < OmniAI::Transcribe::Transcription
        # @!attribute [rw] operation_name
        #   @return [String, nil] the batch operation, e.g. "projects/P/locations/us/operations/123"; nil when sync
        attr_accessor :operation_name

        # @!attribute [rw] billed_duration
        #   @return [Float, nil] seconds Google billed (`totalBilledDuration`); nil when not reported
        attr_accessor :billed_duration
      end
    end
  end
end

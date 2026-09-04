# frozen_string_literal: true

module OmniAI
  module Google
    # Raised when Gemini refuses the prompt itself (`promptFeedback.blockReason`).
    #
    # Terminal and deterministic — the same prompt is blocked every time — so consumers that
    # retry on StreamError must rescue this first.
    class PromptBlockedError < StreamError
      # @return [String, nil]
      attr_reader :reason

      # @param reason [String, nil]
      def initialize(reason)
        @reason = reason
        super("the prompt was blocked: reason=#{reason.inspect}")
      end
    end
  end
end

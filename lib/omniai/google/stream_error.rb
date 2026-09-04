# frozen_string_literal: true

module OmniAI
  module Google
    # Raised when a streamed generation does not complete.
    #
    # Deliberately has no `#response`: the request returned 200 and the failure arrived inside
    # the stream. Consumers branch on that to decide whether to retry.
    class StreamError < OmniAI::Error
      # Google's own explanation of the failure, verbatim.
      #
      # Named for what it holds rather than borrowing `value` from FinishReason, which is a
      # provider enum rather than prose. Kept off `#message` because consumers log that and
      # this text can echo request content -- a deliberate departure from HTTPError, which puts
      # the whole response body into its message.
      #
      # @return [String, nil]
      attr_reader :provider_message

      # @param message [String, nil]
      # @param provider_message [String, nil]
      def initialize(message = nil, provider_message: nil)
        @provider_message = provider_message
        super(message)
      end
    end
  end
end

# frozen_string_literal: true

module OmniAI
  module Google
    # Raised when a streamed generation does not complete.
    #
    # Deliberately has no `#response`: the request returned 200 and the failure arrived inside
    # the stream. Consumers branch on that to decide whether to retry.
    class StreamError < OmniAI::Error
      # Google's own explanation of the failure. Kept off `#message` because consumers log
      # that and it can echo request content; available here when a caller wants it.
      #
      # @return [String, nil]
      attr_reader :detail

      def initialize(message, detail: nil)
        @detail = detail
        super(message)
      end
    end
  end
end

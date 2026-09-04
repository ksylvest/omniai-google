# frozen_string_literal: true

module OmniAI
  module Google
    # Raised when a streamed generation does not complete.
    #
    # Deliberately has no `#response`: the request returned 200 and the failure arrived inside
    # the stream. Consumers branch on that to decide whether to retry.
    class StreamError < OmniAI::Error; end
  end
end

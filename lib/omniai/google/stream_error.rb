# frozen_string_literal: true

module OmniAI
  module Google
    # Raised when a streamed generation does not complete.
    #
    # DELIBERATELY does not carry a `#response`, unlike `OmniAI::HTTPError`. There is no HTTP
    # error to carry: the request succeeded with a 200 and the failure arrived inside the stream
    # afterwards, so attaching a response would mean inventing one. It also matters downstream —
    # consumers commonly branch on whether an error exposes a response to decide between "the
    # server answered and said no" (do not retry) and "the call did not complete" (retry). This
    # is the second kind, and a stream that stopped early is worth retrying.
    class StreamError < OmniAI::Error; end
  end
end

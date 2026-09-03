# frozen_string_literal: true

module OmniAI
  module Google
    # Raised when a stream ends without every candidate reporting a `finishReason`.
    #
    # A completed generation always carries one -- STOP, MAX_TOKENS, SAFETY. Its absence means
    # the generation was cut off, and the aggregate assembled so far is a fragment rather than
    # an answer. Google's own client raises on the same condition.
    #
    # Separate from StreamError so a consumer can tell "upstream told us it failed" from "the
    # stream simply stopped", which are different things to alert on; rescue StreamError to
    # catch both.
    class IncompleteStreamError < StreamError; end
  end
end

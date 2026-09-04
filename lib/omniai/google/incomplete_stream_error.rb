# frozen_string_literal: true

module OmniAI
  module Google
    # Raised when a stream ends with no `finishReason` and produced nothing but thinking.
    # Rescue StreamError to catch this and stream errors together.
    class IncompleteStreamError < StreamError; end
  end
end

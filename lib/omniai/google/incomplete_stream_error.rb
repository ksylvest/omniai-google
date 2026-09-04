# frozen_string_literal: true

module OmniAI
  module Google
    # Raised when a stream ends with no `finishReason` and produced nothing but thinking.
    # Rescue StreamError to catch this and stream errors together. `#provider_message` is
    # always nil here -- there is no provider error to carry.
    class IncompleteStreamError < StreamError; end
  end
end

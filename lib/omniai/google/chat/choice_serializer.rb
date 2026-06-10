# frozen_string_literal: true

module OmniAI
  module Google
    class Chat
      # Overrides choice serialize / deserialize.
      module ChoiceSerializer
        # Maps Gemini candidate `finishReason` values onto the normalized OmniAI::Chat::FinishReason symbols. The
        # entire content-policy / safety family maps to `:filter`; unrecognized values (e.g. OTHER,
        # MALFORMED_FUNCTION_CALL, FINISH_REASON_UNSPECIFIED) fall through to `:other`.
        FINISH_REASONS = {
          "STOP" => OmniAI::Chat::FinishReason::STOP,
          "MAX_TOKENS" => OmniAI::Chat::FinishReason::LENGTH,
          "SAFETY" => OmniAI::Chat::FinishReason::FILTER,
          "RECITATION" => OmniAI::Chat::FinishReason::FILTER,
          "LANGUAGE" => OmniAI::Chat::FinishReason::FILTER,
          "BLOCKLIST" => OmniAI::Chat::FinishReason::FILTER,
          "PROHIBITED_CONTENT" => OmniAI::Chat::FinishReason::FILTER,
          "SPII" => OmniAI::Chat::FinishReason::FILTER,
          "IMAGE_SAFETY" => OmniAI::Chat::FinishReason::FILTER,
        }.freeze
        # @param choice [OmniAI::Chat::Choice]
        # @param context [Context]
        # @return [Hash]
        def self.serialize(choice, context:)
          content = choice.message.serialize(context:)
          { content: }
        end

        # @param data [Hash]
        # @param context [Context]
        # @return [OmniAI::Chat::Choice]
        def self.deserialize(data, context:)
          message = OmniAI::Chat::Message.deserialize(data["content"], context:)
          finish_reason = OmniAI::Chat::FinishReason.deserialize(data["finishReason"], table: FINISH_REASONS)
          OmniAI::Chat::Choice.new(message:, finish_reason:)
        end
      end
    end
  end
end

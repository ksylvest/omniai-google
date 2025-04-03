# frozen_string_literal: true

module OmniAI
  module Google
    # @example
    #   OmniAI::Google::Credentials.parse(Google::Auth::ServiceAccountCredentials.make_creds(...))
    #   OmniAI::Google::Credentials.parse(File.open("./credentials.json"))
    #   OmniAI::Google::Credentials.parse("./credentials.json")
    module Credentials
      SCOPE = %w[https://www.googleapis.com/auth/cloud-platform].join(",")

      # @return [Google::Auth::ServiceAccountCredentials, nil]
      def self.detect
        case
        when ENV.key?("GOOGLE_CREDENTIALS_PATH") then parse(Pathname.new(ENV.fetch("GOOGLE_CREDENTIALS_PATH")))
        when ENV.key?("GOOGLE_CREDENTIALS_JSON") then parse(StringIO.new(ENV.fetch("GOOGLE_CREDENTIALS_JSON")))
        end
      end

      # @param value [Google::Auth::ServiceAccountCredentials, IO, Pathname, String nil]
      # @return [Google::Auth::ServiceAccountCredentials]
      def self.parse(value)
        case value
        when ::Google::Auth::ServiceAccountCredentials then value
        when IO, StringIO then ::Google::Auth::ServiceAccountCredentials.make_creds(json_key_io: value, scope: SCOPE)
        when Pathname then parse(File.open(value))
        when String then parse(StringIO.new(value))
        end
      end
    end
  end
end

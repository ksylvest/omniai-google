# frozen_string_literal: true

RSpec.describe OmniAI::Google::StreamError do
  it "can be raised bare, like every other error in the family" do
    expect { raise described_class }.to raise_error(described_class)
  end

  it "carries no response, so callers classify it as a connection failure" do
    expect(described_class.new("x")).not_to respond_to(:response)
  end

  it "keeps the provider message off the exception message" do
    error = described_class.new("code=503", provider_message: "overloaded")
    expect(error.message).to eql("code=503")
    expect(error.provider_message).to eql("overloaded")
  end
end

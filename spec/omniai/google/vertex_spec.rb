# frozen_string_literal: true

RSpec.describe OmniAI::Google::Vertex do
  describe ".host" do
    it { expect(described_class.host("global")).to eql("https://aiplatform.googleapis.com") }
    it { expect(described_class.host("us")).to eql("https://aiplatform.us.rep.googleapis.com") }
    it { expect(described_class.host("eu")).to eql("https://aiplatform.eu.rep.googleapis.com") }
    it { expect(described_class.host("us-central1")).to eql("https://us-central1-aiplatform.googleapis.com") }
  end
end

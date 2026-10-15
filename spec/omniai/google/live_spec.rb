# frozen_string_literal: true

require_relative "../../support/fake_live_server"

RSpec.describe OmniAI::Google::Live do
  let(:credentials) { instance_double(Google::Auth::ServiceAccountCredentials) }
  let(:log) { StringIO.new }
  let(:client) do
    OmniAI::Google::Client.new(project_id: "test-project", location_id: "us", credentials:, host: server.host,
      logger: Logger.new(log))
  end
  let(:events) { Queue.new }
  let(:handler) { ->(event) { events << event } }
  let(:options) { {} }
  let(:sessions) { [] }

  let(:weather) do
    OmniAI::Tool.new(
      ->(city:) { "Sunny in #{city}" },
      name: "weather",
      description: "Look up the weather",
      parameters: OmniAI::Schema.object(properties: { city: OmniAI::Schema.string }, required: %i[city])
    )
  end

  let(:script) do
    lambda do |connection, message|
      connection.reply({ setupComplete: { sessionId: "session-1" } }) if message.key?("setup")
    end
  end
  let(:server) { FakeLiveServer.new { |connection, message| script.call(connection, message) } }

  def open_session(**overrides)
    described_class.open(client:, model: "gemini-3.8-live", **options, **overrides, &handler).tap { |s| sessions << s }
  end

  # @return [Array] events received until the block returns true (or the timeout)
  def collect_events(until_class:, timeout: 2)
    received = []
    deadline = Time.now + timeout
    while Time.now < deadline
      event = begin
        events.pop(timeout: deadline - Time.now)
      rescue ThreadError
        nil
      end
      break unless event

      received << event
      break if event.is_a?(until_class)
    end
    received
  end

  def next_message(timeout: 2)
    server.messages.pop(timeout:)
  end

  before do
    allow(credentials).to receive(:fetch_access_token!)
    allow(credentials).to receive(:access_token).and_return("token")
  end

  after do
    sessions.each(&:close)
    server.stop
  end

  describe ".open" do
    let(:options) do
      {
        system: "You are an intake assistant.",
        tools: [weather],
        voice: "Kore",
        vad: { start_sensitivity: :high, silence_ms: 800 },
      }
    end

    it "sends the setup with the Vertex model path and returns once setup completes" do
      session = open_session
      expect(session.session_id).to eql("session-1")
      expect(session).to be_open
      expect(next_message).to eql("setup" => {
        "model" => "projects/test-project/locations/us/publishers/google/models/gemini-3.8-live",
        "generationConfig" => {
          "responseModalities" => ["AUDIO"],
          "speechConfig" => { "voiceConfig" => { "prebuiltVoiceConfig" => { "voiceName" => "Kore" } } },
        },
        "systemInstruction" => { "parts" => [{ "text" => "You are an intake assistant." }] },
        "tools" => [{ "functionDeclarations" => [{
          "name" => "weather",
          "description" => "Look up the weather",
          "parameters" => { "type" => "object", "properties" => { "city" => { "type" => "string" } },
                            "required" => ["city"], },
          "behavior" => "BLOCKING",
        }] }],
        "inputAudioTranscription" => {},
        "outputAudioTranscription" => {},
        "realtimeInputConfig" => { "automaticActivityDetection" => {
          "startOfSpeechSensitivity" => "START_SENSITIVITY_HIGH", "silenceDurationMs" => 800,
        } },
      })
    end

    it "authenticates the upgrade with a fresh access token" do
      open_session
      expect(server.connections.pop(timeout: 1).env["HTTP_AUTHORIZATION"]).to eql("Bearer token")
      open_session
      expect(credentials).to have_received(:fetch_access_token!).twice
    end

    it "connects to the BidiGenerateContent path" do
      open_session
      expect(server.connections.pop(timeout: 1).env["PATH_INFO"])
        .to eql("/ws/google.cloud.aiplatform.v1.LlmBidiService/BidiGenerateContent")
    end

    context "with per-tool behavior, compression and resumption" do
      let(:options) do
        { tools: [weather], tool_behavior: { "weather" => :non_blocking }, transcription: false, compression: true,
          resumption: "handle-1", }
      end

      it "sends them in the setup" do
        open_session
        setup = next_message["setup"]
        expect(setup.dig("tools", 0, "functionDeclarations", 0, "behavior")).to eql("NON_BLOCKING")
        expect(setup).not_to include("inputAudioTranscription", "outputAudioTranscription")
        expect(setup["contextWindowCompression"]).to eql("slidingWindow" => {})
        expect(setup["sessionResumption"]).to eql("handle" => "handle-1")
      end
    end

    context "with compression thresholds" do
      let(:options) { { compression: { trigger_tokens: 10_000, target_tokens: 5_000 } } }

      it "sends the trigger and the sliding-window target" do
        open_session
        expect(next_message.dig("setup", "contextWindowCompression"))
          .to eql("triggerTokens" => 10_000, "slidingWindow" => { "targetTokens" => 5_000 })
      end
    end

    context "when the server rejects the setup" do
      let(:script) do
        lambda do |connection, _message|
          connection.close(1008, "Publisher model projects/test-project/... was not found: secret detail")
        end
      end

      it "raises with the close code but without Google's reason" do
        expect { open_session }.to raise_error(described_class::Error) { |error|
          expect(error.code).to be(1008)
          expect(error.reason).to include("secret detail")
          expect(error.message).not_to include("secret detail")
        }
      end
    end

    context "without credentials" do
      let(:client) { OmniAI::Google::Client.new(api_key: "fake", project_id: "test-project", location_id: "us") }

      it { expect { open_session }.to raise_error(ArgumentError, /Vertex credentials/) }
    end
  end

  describe "#send_audio" do
    let(:audio_out) { "\x01\x02".b * 8 }
    let(:script) do
      lambda do |connection, message|
        if message.key?("setup")
          connection.reply({ setupComplete: { sessionId: "session-1" } })
        elsif message.dig("realtimeInput", "audio")
          connection.reply({ serverContent: { inputTranscription: { text: "Hello there" } } })
          connection.reply({ serverContent: { modelTurn: { parts: [{ inlineData: {
            mimeType: "audio/pcm;rate=24000", data: Base64.strict_encode64(audio_out),
          } }] } } }, binary: false)
          connection.reply({ serverContent: { outputTranscription: { text: "Hi!" } } })
          connection.reply({
            serverContent: { turnComplete: true },
            usageMetadata: { promptTokenCount: 524, candidatesTokenCount: 88, totalTokenCount: 708,
                             thoughtsTokenCount: 96, },
          })
        end
      end
    end

    it "streams PCM16 16 kHz audio as realtime input" do
      session = open_session
      next_message
      session.send_audio("\x00\x01".b * 4)
      expect(next_message).to eql("realtimeInput" => { "audio" => {
        "mimeType" => "audio/pcm;rate=16000", "data" => Base64.strict_encode64("\x00\x01".b * 4),
      } })
    end

    it "yields transcripts, decoded audio, turn completion and usage in order" do
      open_session.send_audio("\x00\x01".b)
      received = collect_events(until_class: described_class::Event::Usage)

      expect(received.map(&:class)).to eql([
        described_class::Event::Transcript, described_class::Event::Audio, described_class::Event::Transcript,
        described_class::Event::TurnComplete, described_class::Event::Usage,
      ])
      expect(received[0]).to have_attributes(role: :user, text: "Hello there")
      expect(received[1]).to have_attributes(data: audio_out, mime_type: "audio/pcm;rate=24000")
      expect(received[2]).to have_attributes(role: :model, text: "Hi!")
      expect(received[4].usage).to have_attributes(input_tokens: 524, output_tokens: 184, thinking_tokens: 96,
        total_tokens: 708)
    end

    it "never logs audio or transcripts" do
      open_session.send_audio("\x00\x01".b)
      collect_events(until_class: described_class::Event::Usage)
      expect(log.string).to include("LIVE connect")
      expect(log.string).not_to include("Hello there", "Hi!", Base64.strict_encode64("\x00\x01".b))
    end
  end

  describe "#send_text and #end_audio" do
    it "sends a complete client turn and the end of the audio stream" do
      session = open_session
      next_message
      session.send_text("You are at question Q12.")
      expect(next_message).to eql("clientContent" => {
        "turns" => [{ "role" => "user", "parts" => [{ "text" => "You are at question Q12." }] }],
        "turnComplete" => true,
      })
      session.end_audio
      expect(next_message).to eql("realtimeInput" => { "audioStreamEnd" => true })
    end
  end

  describe "tool calls" do
    let(:options) { { tools: [weather, failing] } }
    let(:failing) do
      OmniAI::Tool.new(->(**) { raise "lookup failed for Jane Doe" }, name: "failing", description: "Fails",
        parameters: OmniAI::Schema.object(properties: {}))
    end
    let(:calls) { [{ id: "fc_1", name: "weather", args: { city: "Fresno" } }] }
    let(:script) do
      lambda do |connection, message|
        if message.key?("setup")
          connection.reply({ setupComplete: { sessionId: "session-1" } })
          connection.reply({ toolCall: { functionCalls: calls } })
        end
      end
    end

    it "yields the call, runs the tool and sends its output" do
      open_session
      next_message
      expect(next_message).to eql("toolResponse" => { "functionResponses" => [
        { "id" => "fc_1", "name" => "weather", "response" => { "output" => "Sunny in Fresno" } },
      ] })
      tool_call = collect_events(until_class: described_class::Event::ToolCall).last
      expect(tool_call.calls.first).to have_attributes(id: "fc_1", name: "weather", arguments: { "city" => "Fresno" })
    end

    context "when the tool raises" do
      let(:calls) { [{ id: "fc_2", name: "failing", args: {} }] }

      it "responds with only the error class and keeps the session open" do
        session = open_session
        next_message
        expect(next_message).to eql("toolResponse" => { "functionResponses" => [
          { "id" => "fc_2", "name" => "failing", "response" => { "error" => "RuntimeError" } },
        ] })
        expect(session).to be_open
        expect(log.string).not_to include("Jane Doe")
      end
    end

    context "when the tool is unknown" do
      let(:calls) { [{ id: "fc_3", name: "missing", args: {} }] }

      it "responds with an error" do
        open_session
        next_message
        expect(next_message.dig("toolResponse", "functionResponses", 0, "response"))
          .to eql("error" => "unknown tool: missing")
      end
    end

    context "when the session has no tools" do
      let(:options) { { tools: nil } }

      it "responds with an unknown-tool error" do
        open_session
        next_message
        expect(next_message.dig("toolResponse", "functionResponses", 0, "response"))
          .to eql("error" => "unknown tool: weather")
      end
    end

    context "when the server cancels calls" do
      let(:script) do
        lambda do |connection, message|
          if message.key?("setup")
            connection.reply({ setupComplete: { sessionId: "session-1" } })
            connection.reply({ toolCallCancellation: { ids: %w[fc_1] } })
          end
        end
      end

      it "yields the cancelled ids" do
        open_session
        event = collect_events(until_class: described_class::Event::ToolCallCancellation).last
        expect(event.ids).to eql(%w[fc_1])
      end
    end
  end

  describe "server notices" do
    let(:script) do
      lambda do |connection, message|
        if message.key?("setup")
          connection.reply({ setupComplete: { sessionId: "session-1" } })
          connection.reply({ voiceActivity: { type: "ACTIVITY_START", audioOffset: "0.200s" } })
          connection.reply({ serverContent: { interrupted: true } })
          connection.reply({ sessionResumptionUpdate: { newHandle: "handle-2", resumable: true } })
          connection.reply({ goAway: { timeLeft: "50s" } })
        end
      end
    end

    it "yields voice activity, interruption, resumption and go-away" do
      open_session
      received = collect_events(until_class: described_class::Event::GoAway)
      expect(received.map(&:class)).to eql([
        described_class::Event::VoiceActivity, described_class::Event::Interrupted,
        described_class::Event::ResumptionUpdate, described_class::Event::GoAway,
      ])
      expect(received[0]).to have_attributes(type: :start, offset: 0.2)
      expect(received[2]).to have_attributes(handle: "handle-2", resumable: true)
      expect(received[3]).to have_attributes(time_left: 50.0)
    end
  end

  describe "closing" do
    it "yields Closed once when the client closes" do
      session = open_session
      session.close
      session.close
      closed = collect_events(until_class: described_class::Event::Closed)
      expect(closed.grep(described_class::Event::Closed).size).to be(1)
      expect(session).not_to be_open
      expect { session.send_audio("\x00".b) }.to raise_error(described_class::ClosedError)
    end

    context "when the server closes with an error" do
      let(:script) do
        lambda do |connection, message|
          if message.key?("setup")
            connection.reply({ setupComplete: { sessionId: "session-1" } })
            connection.close(1011, "internal error mentioning claimant words")
          end
        end
      end

      it "yields Closed with the code and keeps the reason out of inspect" do
        session = open_session
        closed = collect_events(until_class: described_class::Event::Closed).last
        expect(closed.code).to be(1011)
        expect(closed.reason).to include("claimant words")
        expect(closed.inspect).not_to include("claimant words")
        expect(session).not_to be_open
        expect(log.string).to include("LIVE close 1011 session-1")
        expect(log.string).not_to include("claimant words")
      end
    end

    context "when the connection drops without a close frame (EOF)" do
      let(:script) do
        lambda do |connection, message|
          if message.key?("setup")
            connection.reply({ setupComplete: { sessionId: "session-1" } })
            connection.drop!
          end
        end
      end

      it "yields Closed instead of dying silently" do
        session = open_session
        closed = collect_events(until_class: described_class::Event::Closed).last
        expect(closed).to be_a(described_class::Event::Closed)
        expect(closed.code).to be_nil
        expect(session).not_to be_open
      end
    end

    context "when the event handler raises" do
      let(:handler) do
        lambda do |event|
          events << event
          raise "handler bug with claimant words" if event.is_a?(described_class::Event::Interrupted)
        end
      end
      let(:script) do
        lambda do |connection, message|
          if message.key?("setup")
            connection.reply({ setupComplete: { sessionId: "session-1" } })
            connection.reply({ serverContent: { interrupted: true } })
          end
        end
      end

      it "closes the session and yields Closed with the error" do
        session = open_session
        closed = collect_events(until_class: described_class::Event::Closed).last
        expect(closed.error).to be_a(RuntimeError)
        expect(session).not_to be_open
        expect(log.string).not_to include("claimant words")
      end
    end

    context "when the handler closes the session itself" do
      let(:handler) do
        lambda do |event|
          events << event
          sessions.first.close if event.is_a?(described_class::Event::Interrupted)
        end
      end
      let(:script) do
        lambda do |connection, message|
          connection.reply({ setupComplete: { sessionId: "session-1" } }) if message.key?("setup")
          connection.reply({ serverContent: { interrupted: true } }) if message.key?("clientContent")
        end
      end

      it "closes cleanly from the reader thread" do
        session = open_session
        session.send_text("Hello")
        closed = collect_events(until_class: described_class::Event::Closed).last
        expect(closed).to have_attributes(code: 1000, error: nil)
        expect(session).not_to be_open
      end
    end

    context "when the socket stalls" do
      let(:script) do
        lambda do |connection, message|
          if message.key?("setup")
            connection.reply({ setupComplete: { sessionId: "session-1" } })
            connection.stall!
          end
        end
      end

      it "times out the write, closes the session and yields Closed" do
        session = open_session(write_timeout: 0.2)
        chunk = "\x00".b * 1_000_000
        started = Time.now
        expect { 50.times { session.send_audio(chunk) } }.to raise_error(described_class::TimeoutError)
        expect(Time.now - started).to be < 2
        expect(session).not_to be_open
        expect(collect_events(until_class: described_class::Event::Closed).last)
          .to be_a(described_class::Event::Closed)
      end
    end

    context "when the server sends a malformed frame" do
      let(:script) do
        lambda do |connection, message|
          if message.key?("setup")
            connection.reply({ setupComplete: { sessionId: "session-1" } })
            connection.driver.binary('{"serverContent": {"inputTranscription": {"text": "my SSN is'.bytes)
          end
        end
      end

      it "yields Closed with a content-free error" do
        open_session
        closed = collect_events(until_class: described_class::Event::Closed).last
        expect(closed.error).to be_a(described_class::Error)
        expect(closed.error.message).to include("JSON::ParserError", "session-1")
        expect(closed.error.message).not_to include("SSN")
        expect(closed.error.cause).to be_nil
      end
    end

    context "when the server sends a frame that isn't an object" do
      let(:script) do
        lambda do |connection, message|
          if message.key?("setup")
            connection.reply({ setupComplete: { sessionId: "session-1" } })
            connection.driver.binary('["my SSN is 123"]'.bytes)
          end
        end
      end

      it "yields Closed with a content-free error" do
        open_session
        closed = collect_events(until_class: described_class::Event::Closed).last
        expect(closed.error).to be_a(described_class::Error)
        expect(closed.error.message).not_to include("SSN")
      end
    end

    context "when the connection goes silent" do
      before do
        stub_const("OmniAI::Google::Live::Connection::PING_INTERVAL", 0.2)
        stub_const("OmniAI::Google::Live::Connection::PONG_TIMEOUT", 0.3)
      end

      it "keeps a healthy idle session open with pings" do
        session = open_session
        sleep(1)
        expect(session).to be_open
      end
    end

    context "when the peer stops answering pings" do
      let(:script) do
        lambda do |connection, message|
          if message.key?("setup")
            connection.reply({ setupComplete: { sessionId: "session-1" } })
            connection.stall!
          end
        end
      end

      before do
        stub_const("OmniAI::Google::Live::Connection::PING_INTERVAL", 0.2)
        stub_const("OmniAI::Google::Live::Connection::PONG_TIMEOUT", 0.3)
      end

      it "yields Closed once the pong is overdue" do
        session = open_session
        closed = collect_events(until_class: described_class::Event::Closed, timeout: 2).last
        expect(closed).to be_a(described_class::Event::Closed)
        expect(closed.error).to be_a(OmniAI::Google::Live::Connection::PongTimeout)
        expect(session).not_to be_open
      end
    end
  end

  describe "TLS handshake" do
    let(:silent) { TCPServer.new("127.0.0.1", 0) }
    let(:client) do
      OmniAI::Google::Client.new(project_id: "test-project", location_id: "us", credentials:,
        host: "https://127.0.0.1:#{silent.addr[1]}", logger: Logger.new(log))
    end
    let(:accepted) { [] }

    before do
      stub_const("OmniAI::Google::Live::Connection::CONNECT_TIMEOUT", 0.3)
      Thread.new { accepted << silent.accept }
    end

    after do
      accepted.each(&:close)
      silent.close
    end

    it "times out when the peer accepts TCP but never answers TLS" do
      started = Time.now
      expect { open_session }.to raise_error(described_class::TimeoutError, /connect timed out/)
      expect(Time.now - started).to be < 1
    end
  end
end

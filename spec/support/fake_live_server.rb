# frozen_string_literal: true

require "socket"
require "websocket/driver"

# An in-process stand-in for Vertex's BidiGenerateContent WebSocket. Each JSON message the client sends is recorded
# and handed to the script block with the connection, which replies the way Vertex does (binary JSON frames).
class FakeLiveServer
  # The server side of one client connection.
  class Connection
    attr_accessor :env
    attr_reader :driver, :socket

    def initialize(socket)
      @socket = socket
      @driver = WebSocket::Driver.server(self)
      @stalled = false
    end

    # @param message [Hash]
    # @param binary [Boolean] Vertex sends binary frames; text is accepted too
    def reply(message, binary: true)
      json = JSON.generate(message)
      binary ? @driver.binary(json.bytes) : @driver.text(json)
    end

    def close(code, reason)
      @driver.close(reason, code)
    end

    # Drops the TCP connection without a close frame.
    def drop!
      @socket.close
    end

    # Stops reading, so the client's writes eventually block.
    def stall!
      @stalled = true
    end

    def stalled? = @stalled

    def write(data)
      @socket.write(data)
    rescue IOError, SystemCallError
      nil
    end

    def url = "ws://127.0.0.1/"
  end

  attr_reader :port, :messages, :connections

  # @yieldparam connection [Connection]
  # @yieldparam message [Hash]
  def initialize(&script)
    @script = script
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @messages = Queue.new
    @connections = Queue.new
    @threads = []
    @acceptor = Thread.new { accept_loop }
  end

  def host = "http://127.0.0.1:#{@port}"

  def stop
    @server.close
    @acceptor.join(1)
    @threads.each { |thread| thread.kill.join(1) }
  end

private

  def accept_loop
    loop do
      socket = @server.accept
      socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVBUF, 4096)
      @threads << Thread.new(socket) { |client| serve(client) }
    end
  rescue IOError, SystemCallError
    nil
  end

  def serve(socket)
    connection = Connection.new(socket)
    driver = connection.driver
    driver.on(:connect) do
      connection.env = driver.env
      @connections << connection
      driver.start
    end
    driver.on(:message) do |event|
      data = event.data.is_a?(Array) ? event.data.pack("C*") : event.data
      message = JSON.parse(data)
      @messages << message
      @script&.call(connection, message)
    end

    loop do
      if connection.stalled?
        sleep(0.05)
        next
      end
      driver.parse(socket.readpartial(16_384))
    end
  rescue IOError, SystemCallError
    nil
  end
end

# frozen_string_literal: true

require "socket"
require "websocket/driver"

module OmniAI
  module Google
    class Live
      # A WebSocket client over TCP or TLS, driven by websocket-driver with one reader thread per connection.
      #
      # Callbacks run on the reader thread. Writes may come from any thread: they are serialized by a mutex and bounded
      # by `write_timeout`, so a stalled peer can't block the caller indefinitely. `on_close` is called exactly once,
      # whether the peer closes, the socket hits EOF or errors, a write times out, or a callback raises.
      class Connection
        CONNECT_TIMEOUT = 10 # seconds
        CLOSE_TIMEOUT = 2 # seconds
        READ_CHUNK = 16_384 # bytes

        class WriteTimeout < StandardError; end

        # @return [String]
        attr_reader :url

        # @param url [String] a ws:// or wss:// URL
        # @param headers [Hash] sent with the upgrade request
        # @param write_timeout [Numeric] seconds
        # @param on_open [Proc] called with no arguments
        # @param on_message [Proc] called with the payload String
        # @param on_close [Proc] called with (code, reason, error)
        def initialize(url:, headers:, write_timeout:, on_open:, on_message:, on_close:)
          @url = url
          @headers = headers
          @write_timeout = write_timeout
          @on_open = on_open
          @on_message = on_message
          @on_close = on_close
          @mutex = Mutex.new
          @pending = []
          @finished = false
        end

        def connect
          @io = open_socket
          @driver = WebSocket::Driver.client(self, binary_data_format: :string)
          @headers.each { |name, value| @driver.set_header(name, value) }
          @driver.on(:open) { @pending << [:open] }
          @driver.on(:message) { |event| @pending << [:message, event.data] }
          @driver.on(:close) { |event| @pending << [:close, event.code, event.reason] }
          @mutex.synchronize { @driver.start }
          @reader = Thread.new { read_loop }
          @reader.name = "omniai-google-live"
          @reader.report_on_exception = false
        end

        # @return [Boolean]
        def open?
          !@finished
        end

        # @param payload [String]
        #
        # @raise [WriteTimeout]
        def send_text(payload)
          @mutex.synchronize { @driver.text(payload) }
        rescue WriteTimeout => e
          abort!(e)
          raise
        end

        # Sends a close frame and waits briefly for the peer's reply before dropping the socket. Called from a callback
        # (the reader thread itself), it only sends the frame: the reader finishes when the reply arrives.
        def close
          return if @finished || @reader.nil?

          begin
            @mutex.synchronize { @driver.close }
          rescue WriteTimeout, IOError, SystemCallError
            nil
          end
          return if Thread.current == @reader

          abort! unless @reader.join(CLOSE_TIMEOUT)
          @reader.join(CLOSE_TIMEOUT)
        end

        # Called by websocket-driver (under the mutex) for every outgoing frame.
        #
        # @param data [String]
        def write(data)
          deadline = monotonic + @write_timeout
          data = data.b
          until data.empty?
            result = @io.write_nonblock(data, exception: false)
            case result
            when :wait_writable then wait!(nil, [@io.to_io], deadline)
            when :wait_readable then wait!([@io.to_io], nil, deadline)
            else data = data.byteslice(result..)
            end
          end
        end

      private

        # @return [Socket, OpenSSL::SSL::SSLSocket]
        def open_socket
          uri = URI.parse(@url)
          tcp = Socket.tcp(uri.host, uri.port, connect_timeout: CONNECT_TIMEOUT)
          return tcp unless uri.scheme == "wss"

          context = OpenSSL::SSL::SSLContext.new
          context.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER)
          ssl = OpenSSL::SSL::SSLSocket.new(tcp, context)
          ssl.hostname = uri.host
          ssl.sync_close = true
          ssl.connect
          ssl
        end

        def read_loop
          loop do
            data = @io.readpartial(READ_CHUNK)
            events = @mutex.synchronize do
              @driver.parse(data)
              @pending.slice!(0..)
            end
            events.each { |event| dispatch(*event) }
            break if @finished
          end
        rescue EOFError
          finish(nil, nil, @abort_error)
        rescue IOError, SystemCallError, OpenSSL::SSL::SSLError => e
          finish(nil, nil, @abort_error || e)
        rescue StandardError => e # a callback raised
          finish(nil, nil, e)
        ensure
          finish(nil, nil, @abort_error)
        end

        def dispatch(type, *args)
          case type
          when :open then @on_open.call
          when :message then @on_message.call(args.first)
          when :close then finish(args[0], args[1], nil)
          end
        end

        # Drops the socket; the reader thread then finishes with `error`.
        def abort!(error = nil)
          @abort_error ||= error
          @io.close
        rescue IOError, SystemCallError
          nil
        end

        def finish(code, reason, error)
          return if @finished

          @finished = true
          begin
            @io.close
          rescue IOError, SystemCallError
            nil
          end
          begin
            @on_close.call(code, reason, error)
          rescue StandardError
            nil
          end
        end

        def wait!(readers, writers, deadline)
          remaining = deadline - monotonic
          return if remaining.positive? && IO.select(readers, writers, nil, remaining)

          raise WriteTimeout, "write timed out after #{@write_timeout}s"
        end

        def monotonic
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end

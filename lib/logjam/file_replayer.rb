require 'fileutils'
require 'eventmachine'
require 'amqp'
require 'oj'

module Logjam

  class FileReplayer

    def initialize(config_name, logfile_name)
      @stream = Logjam.streams[config_name]
      @app = @stream.app
      @env = @stream.env
      @key = "logs.#{@app}.#{@env}"
      @io = logfile_io(logfile_name)
    end

    def process
      EM.run do
        @amqp_connection = AMQP.start(:host => "127.0.0.1")
        @channel = AMQP::Channel.new(@amqp_connection)
        @exchange = @channel.topic(exchange_name, :durable => true)
        @connection = EM.watch @io, SimpleGrep
        @connection.importer = self
        @connection.notify_readable = true
        trap("INT") { stop }
      end
    end

    def exchange_name
      [@stream.importer.exchange, @app, @env].compact.join("-")
    end

    def publish(line)
      @exchange.publish(line, :key => @key)
    end

    def stop
      @connection.detach
      @io.close
      @amqp_connection.close { EM.stop_event_loop }
    end

    private

    def logfile_io(logfile_name)
      cmd = logfile_name =~ /\.gz$/ ? "gzcat" : "cat"
      IO.popen("#{cmd} #{logfile_name}", "rb")
    end

    module SimpleGrep
      attr_reader :line_count
      attr_writer :importer
      def post_init
        @line_count = 0
        @start_time = Time.now
      end
      def unbind
        elapsed = Time.now - @start_time
        speed = @line_count / elapsed
        printf "\nprocessed %d lines (%d/second)\n", @line_count, speed.to_i
      end
      def notify_readable
        @line_count += 1
        @importer.publish @io.readline
      rescue EOFError
        @importer.stop
      end
    end

  end
end

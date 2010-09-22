require 'fileutils'
require 'eventmachine'
require 'amqp'
require 'mq'
require 'json'

module Logjam

  class FileImporter
    attr_reader :logfile_name

    def initialize(logfile_name, app="app", env="production")
      @io = logfile_io(logfile_name)
      @app = app
      @env = env
    end

    def process
      EM.run do
        connection = EM.watch @io, SimpleGrep
        connection.importer = self
        connection.notify_readable = true
        trap("INT") { connection.detach; EM.stop_event_loop }
        initialize_exchange
      end
    end

    def publish(hash)
      payload = hash.to_json
      @exchange.publish(payload, :key => key)
    end

    private

    def key
      @key ||= "logs.#{@app}"
    end

    def initialize_exchange
      @channel = MQ.new(AMQP::connect(:host => "127.0.0.1"))
      @exchange = @channel.topic("logjam-development-exchange", :durable => true, :auto_delete => false)
    end

    def logfile_io(logfile_name)
      cmd = logfile_name =~ /\.gz$/ ? "gzcat" : "cat"
      IO.popen("#{cmd} #{logfile_name}", "rb")
    end

    module SimpleGrep
      attr_reader :line_count
      attr_writer :importer
      def post_init
        @line_count = 0
      end
      def unbind
        puts "processed #{@line_count} lines"
      end
      def notify_readable
        @line_count += 1
        Parser.parse_line(@io.readline){|entry| @importer.publish entry.to_hash}
      rescue EOFError
        detach
        @io.close
        EM.stop_event_loop
      end
    end

  end
end

require 'fileutils'
require 'eventmachine'
require 'amqp'
require 'json'

module Logjam

  class FileImporter

    def initialize(config_name, logfile_name)
      @stream = Logjam.streams[config_name]
      @app = @stream.app
      @env = @stream.env
      @importer = MongoImporter.new(@stream)
      @io = logfile_io(logfile_name)
    end

    def process
      EM.run do
        connection = EM.watch @io, SimpleGrep
        connection.importer = @importer
        connection.notify_readable = true
        trap("INT") { connection.detach; EM.stop_event_loop }
        @timer = EM.add_periodic_timer(1) do
          @importer.flush_buffers(false)
        end
      end
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
      end
      def unbind
        puts "processed #{@line_count} lines"
      end
      def notify_readable
        @line_count += 1
        line = @io.readline
        entry = JSON.parse line
        @importer.add_entry entry
      rescue EOFError
        detach
        @io.close
        EM.stop_event_loop
      end
    end

  end
end

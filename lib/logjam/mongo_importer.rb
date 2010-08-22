require 'fileutils'
require 'eventmachine'

module Logjam

  class MongoImporter < Importer
    def initialize(*args)
      super
      @mongo_buffers = {}
      @request_count = 0
    end

    def mongo_buffer(hash)
      date_str = hash[:started_at][0..9]
      app = hash[:app] || "app"
      env = hash[:env] || "production"
      key = Logjam.db_name(date_str, app, env)
      @mongo_buffers[key] ||= MongoImportBuffer.new(key, app, env)
    end

    def add_entry(entry)
      mongo_buffer(entry).add entry
      @request_count += 1
    end

    def flush_buffers
      puts "flushing #{@request_count} requests"
      @mongo_buffers.each_value{|b| b.flush}
      @mongo_buffers = {}
      @request_count = 0
    end

    private

    module SimpleGrep
      attr_reader :line_count
      attr_writer :importer
      def post_init
        @line_count = 0
      end
      def unbind
        puts "processed #{@line_count} lines"
        @importer.flush_buffers
      end
      def notify_readable
        @line_count += 1
        Parser.parse_line(@io.readline){|entry| @importer.add_entry entry.to_hash}
      rescue EOFError
        detach
        @io.close
        EM.stop_event_loop
      end
    end

    def process_internal
      EM.run do
        connection = EM.watch logfile_io, SimpleGrep
        connection.importer = self
        connection.notify_readable = true
        EM.add_periodic_timer(1){ flush_buffers }
        trap("INT") { connection.detach; EM.stop_event_loop }
      end
    end

    def logfile_already_imported?
      false
    end

    def create_import_record
    end

  end
end

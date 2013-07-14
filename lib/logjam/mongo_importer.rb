module Logjam

  class MongoImporter

    include Helpers

    def initialize(stream, zmq_context)
      @import_buffers = {}
      @request_count = 0
      @stream = stream
      @publisher = LiveStreamPublisher.new(@stream, zmq_context)
    end

    def stop
      @publisher.stop
    end

    def import_buffer(db_name)
      @import_buffers[db_name] ||=
        begin
          log_info "creating import buffer #{db_name}"
          MongoImportBuffer.new(db_name, @publisher)
        end
    end

    def process(states)
      # log_info "received states: #{states.inspect}"
      states.each do |infos|
        infos.each do |db_name,values|
          buffer = import_buffer(db_name)
          @request_count += buffer.add_values(values)
        end
      end
      flush_buffers_and_publish
    end

    def flush_buffers_and_publish
      log_info("flushing %5d requests" % [@request_count])
      @import_buffers.each_value do |buffer|
        buffer.flush_and_publish
      end
      clean_old_buffers
    rescue Exception
      log_error $!.inspect
    ensure
      @request_count = 0
    end

    def clean_old_buffers
      current_db_name = Logjam.db_name(Date.today, @stream.app, @stream.env)
      @import_buffers.delete_if{|db_name,_| db_name != current_db_name}
    end
  end
end

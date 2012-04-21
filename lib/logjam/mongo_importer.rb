module Logjam

  class MongoImporter

    include LogWithProcessId

    def initialize(stream)
      @mongo_buffers = {}
      @request_count = 0
      @stream = stream
      @delete_old_buffers = Rails.env != "development"
      @publisher = LiveStreamPublisher.new(@stream)
    end

    def mongo_buffer(db_name)
      @mongo_buffers[db_name] ||=
        begin
          log_info "creating import buffer #{db_name}"
          MongoImportBuffer.new(db_name, @publisher)
        end
    end

    def process(states)
      # log_info "received states: #{states.inspect}"
      states.each do |infos|
        infos.each do |dbname,values|
          buffer = mongo_buffer(dbname)
          @request_count += buffer.add_values(values)
        end
      end
      flush_buffers_and_publish
    end

    def flush_buffers_and_publish
      log_info "flushing #{@request_count} requests"
      today = Date.today.to_s
      @mongo_buffers.keys.each do |key|
        buffer = @mongo_buffers[key]
        buffer.flush_and_publish
        @mongo_buffers.delete(key) if @delete_old_buffers && buffer.iso_date_string != today
      end
    rescue Exception
      log_error $!.inspect
    ensure
      @request_count = 0
    end

  end
end

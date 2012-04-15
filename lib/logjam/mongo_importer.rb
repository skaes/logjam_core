module Logjam

  class MongoImporter

    include LogWithProcessId

    def initialize(stream)
      @mongo_buffers = {}
      @request_count = 0
      @stream = stream
      @app = stream.app
      @env = stream.env
      $stdout.sync = true
      $stderr.sync = true
      @delete_old_buffers = Rails.env != "development"
      @publisher = LiveStreamPublisher.new(@app, @env)
      @processor = RequestProcessorProxy.new(@app, @env, 2)
    end

    def mongo_buffer(hash)
      date_str = hash["started_at"][0..9]
      key = Logjam.db_name(date_str, @app, @env)
      @mongo_buffers[key] ||=
        begin
          log_info "creating import buffer #{key}"
          # log_info hash.to_yaml
          MongoImportBuffer.new(key, @app, @env, date_str, @processor, @publisher)
        end
    end

    def add_entry(entry)
      mongo_buffer(entry).add entry
      @request_count += 1
    end

    def flush_buffers
      log_info "flushing #{@request_count} requests"
      today = Date.today.to_s
      states = @processor.reset_state
      log_info "received states" # ": #{states.inspect}"
      states.each do |infos|
        infos.each do |dbname,values|
          buffer = @mongo_buffers[dbname]
          buffer.add_values(values)
        end
      end
      @mongo_buffers.keys.each do |key|
        buffer = @mongo_buffers[key]
        buffer.flush
        @mongo_buffers.delete(key) if @delete_old_buffers && buffer.iso_date_string != today
      end
    rescue Exception
      log_error $!.inspect
    ensure
      @request_count = 0
    end

    def shutdown
      log_error "shutting down processor"
      @processor.shutdown
    end
  end
end

module Logjam

  class MongoImporter
    def initialize
      @mongo_buffers = {}
      @request_count = 0
      $stdout.sync = true
      $stderr.sync = true
    end

    def mongo_buffer(hash)
      date_str = hash["started_at"][0..9]
      app = hash.delete(:app) || "app"
      env = hash.delete(:env) || "production"
      key = Logjam.db_name(date_str, app, env)
      @mongo_buffers[key] ||=
        begin
          puts "creating import buffer #{key}"
          # puts hash.to_yaml
          MongoImportBuffer.new(key, app, env, date_str)
        end
    end

    def add_entry(entry)
      mongo_buffer(entry).add entry
      @request_count += 1
    end

    def flush_buffers
      puts "flushing #{@request_count} requests"
      today = Date.today.to_s
      @mongo_buffers.keys.each do |key|
        buffer = @mongo_buffers[key]
        buffer.flush
        @mongo_buffers.delete(key) if buffer.iso_date_string != today
      end
      @request_count = 0
    end
  end
end

module Logjam

  class MongoImporter
    def initialize
      @mongo_buffers = {}
      @request_count = 0
      @creation_date = Date.today
    end

    def mongo_buffer(hash)
      date_str = hash["started_at"][0..9]
      app = hash["app"] || "app"
      env = hash["env"] || "production"
      key = Logjam.db_name(date_str, app, env)
      @mongo_buffers[key] ||=
        begin
          puts "creating import buffer #{key}"
          # puts hash.to_yaml
          MongoImportBuffer.new(key, app, env)
        end
    end

    def add_entry(entry)
      mongo_buffer(entry).add entry
      @request_count += 1
    end

    def flush_buffers
      puts "flushing #{@request_count} requests"
      @mongo_buffers.each_value{|b| b.flush}
      reset_buffers_if_they_were_not_created_today
      @request_count = 0
    end

    def reset_buffers_if_they_were_not_created_today
      today = Date.today
      if today > @creation_date
        @mongo_buffers = {}
        @creation_date = today
      end
    end
  end
end

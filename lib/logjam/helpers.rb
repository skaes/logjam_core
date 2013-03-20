module Logjam
  module Helpers
    def log_info(message)
      puts "LJ[#{$$}]: #{message}"; $stdout.flush
    end

    def log_error(message)
      $stderr.puts "LJ[#{$$}]: #{message}"; $stderr.flush
    end

    def extract_minute_from_iso8601(iso_string)
      60 * iso_string[11..12].to_i + iso_string[14..15].to_i
    end

  end
end

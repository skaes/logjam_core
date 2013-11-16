module Logjam
  module Helpers
    def log_info(message)
      puts "LJI[#{$$}] #{message}"; $stdout.flush
    end

    def log_error(message)
      $stderr.puts "LJE[#{$$}] #{message}"; $stderr.flush
    end

    def log_warn(message)
      $stderr.puts "LJW[#{$$}] #{message}"; $stderr.flush
    end

    def log_backtrace(e)
      log_error(e.backtrace[0..9].join("\nLJE[#{$$}] "))
    end

    def extract_minute_from_iso8601(iso_string)
      60 * iso_string[11..12].to_i + iso_string[14..15].to_i
    end
  end
end

module Logjam
  module LogWithProcessId
    def log_info(message)
      puts "LJ[#{$$}]: #{message}"; $stdout.flush
    end

    def log_error(message)
      $stderr.puts "LJ[#{$$}]: #{message}"; $stderr.flush
    end
  end
end

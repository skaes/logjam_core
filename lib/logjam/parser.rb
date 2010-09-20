module Logjam

  ##
  # LogParser parses a Syslog like log file looking for lines logged by the 'rails'
  # program.
  #
  # LogParser does not work with Rails' default logger because there is no way
  # to group all the log output of a single request. You must use a logger which produces
  # syslog-like formatted logs.

  module Parser
    @unprocessed_requests = {}

    SEVERITIES = Hash.new(1).merge!("DEBUG" => 0,
                                    "INFO"  => 1,
                                    "WARN"  => 2,
                                    "ERROR" => 3,
                                    "FATAL" => 4,
                                    "ANY"   => 5)

    def self.parse_line(line)
      if parts = Matchers::LOG_LINE_SPLITTER.call(line)
        severity1, host, process_id, severity2, user_id, engine, payload = *parts
        severity = SEVERITIES[severity1 || severity2]

        key = "#{host}-#{process_id}"
        if payload =~/^Processing/
          # puts "processing"
          if request = @unprocessed_requests.delete(key)
            puts "incomplete request:"
            puts request.to_yaml
            yield RequestInfo.new(host, process_id, user_id, request)
          end
          @unprocessed_requests[key] = [[severity, payload]]
        elsif payload =~ /^Completed/
          # puts "completed"
          if request = @unprocessed_requests.delete(key)
            yield RequestInfo.new(host, process_id, user_id, request << [severity, payload])
          end
        elsif request = @unprocessed_requests[key]
          # puts "other"
          request << [severity, payload]
        end
      else
        $stderr.puts "no match for line: #{line}"
      end
    rescue Exception => e
      $stderr.puts "Exception occured during log line processing: #{e}: #{e.backtrace.join("\n")}"
      $stderr.puts "Offending log line: #{line}"
    end
  end

end

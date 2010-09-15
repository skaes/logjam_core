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

    SEVERITIES = Hash.new(5).merge!("DEBUG" => 0,
                                    "INFO"  => 1,
                                    "WARN"  => 2,
                                    "ERROR" => 3,
                                    "FATAL" => 4,
                                    "ANY"   => 5)

    def self.parse_line(line)
      if parts = Matchers::LOG_LINE_SPLITTER.call(line)
        severity1, host, process_id, severity2, user_id, engine, payload = *parts
        severity = SEVERITIES[severity1 || severity2]

        # extract generic parameters and stash away the line
        key = "#{host}-#{process_id}"
        (@unprocessed_requests[key] ||= []) << [severity, payload]

        # if this line is a completion line and also has a request header, then we
        # create a request info object and yield it
        if payload =~ /^Completed/
          request = @unprocessed_requests.delete key
          yield RequestInfo.new(host, process_id, user_id, request) if request.any? {|s,l| l =~ /^Processing/}
        end
      else
        $stderr.puts "no match for line: #{line}"
      end
    rescue Exception => e
      $stderr.puts "Exception occured during log line processing: #{e}"
      $stderr.puts "Offending log line: #{line}"
    end
  end

end

##
# LogParser parses a Syslog like log file looking for lines logged by the 'rails'
# program.  A typical log line looks like this:
#
#   Mar  7 00:00:20 online1 rails[59600]: Person Load (0.001884)   SELECT * FROM people WHERE id = 10519 LIMIT 1
#
# LogParser does not work with Rails' default logger because there is no way
# to group all the log output of a single request. You must use a logger which produces
# syslog like formatted logs.

module Parser
  @unprocessed_requests = {}

  def self.parse_line(line)
    if parts = Matchers::LOG_LINE_SPLITTER.call(line)
      host, process_id, user_id, engine, payload = *parts

      # extract generic parameters and stash away the line
      key = "#{host}-#{process_id}"
      (@unprocessed_requests[key] ||= []) << payload

      # if this line is a completion line and also has a request header, then we
      # create a request info object and yield it
      if payload =~ /^Completed/
        request = @unprocessed_requests.delete key
        yield RequestInfo.new(host, process_id, user_id, request) if request.any? {|l| l =~ /^Processing/}
      end
    else
      $stderr.puts "no match for line: #{line}"
    end
  rescue Exception => e
    $stderr.puts "Exception occured during log line processing: #{e}"
    $stderr.puts "Offending log line: #{line}"
  end
end


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
  # Parses IO stream +stream+, yielding a RequestInfo object for each recognizable log
  # entry.
  #
  # Log entries are recognised as starting with Processing, continuing with
  # the same process id through Completed.
  def self.parse(stream, &block) # :yields: request_info
    stream.each_line do |line|
      begin
        parse_line(line, &block)
      rescue Exception => e
        $stderr.puts "Exception occured during log line processing: #{e}"
        $stderr.puts "Offending log line: #{line}"
      end
    end

    # warn user about imcomplete log entries.
    # this is usually caused by rotating logs
    # unless unprocessed_requests.empty?
    #   puts "#{unprocessed_requests.size} actions where incomplete and could not be imported"
    # end
  end

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
  end
end


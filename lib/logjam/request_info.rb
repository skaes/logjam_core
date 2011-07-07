module Logjam
  class RequestInfo
    @@matchers = []
    def self.register_matcher(matcher)
      @@matchers << matcher
    end

    def matchers
      @@matchers
    end

    def initialize(host, process_id, user_id, lines)
      # $stderr.puts lines.inspect
      @info = {:host => host, :process_id => process_id.to_i, :user_id => user_id.to_i, :lines => lines}
      process lines, @info
      unless @info[:action]
        $stderr.puts "action could not be recognized"
        $stderr.puts "log lines: #{lines.inspect}"
      end
    end

    def to_hash
      @info
    end

    def process(lines, info)
      lines.each do |severity, timestamp, line|
        # puts "matching line #{line}"
        matchers.each do |matcher|
          if extracted_values = matcher.call(line)
            # puts "merging #{extracted_values.inspect}"
            info.merge! extracted_values
            break
          end
        end
      end
    end
  end
end


module Logjam
  class RequestInfo
    @@matchers = []
    def self.register_matcher(matcher)
      @@matchers << matcher
    end

    def matchers
      @@matchers
    end

    def initialize(host, process_id, user_id, lines, severity)
      @info = {:host => host, :process_id => process_id.to_i, :user_id => user_id.to_i, :page => nil, :ip => nil, :lines => lines, :severity => severity}
      @info.merge!(default_values)
      process lines
      unless @info[:page]
        $stderr.puts "controller action could not be parsed"
        $stderr.puts "log lines: #{lines.inspect}"
      end
    end

    def extract_minute(iso_string)
      60 * iso_string[11..12].to_i + iso_string[14..15].to_i
    end

    def allocated_memory
      @info[:allocated_bytes] + @info[:allocated_objects] * 40 rescue 0
    end

    def to_hash
      @hash ||=
        begin
          @info.merge! :other_time => other_time, :allocated_memory => allocated_memory
          minute = extract_minute(@info[:started_at])
          @info[:minute] = minute
          @info
        end
    end

    def default_values
      @@default_values ||=
        begin
          d = {}
          Resource.time_resources.map(&:to_sym).each  { |r| d[r] = 0.0 }
          Resource.memory_resources.map(&:to_sym).each { |r| d[r] = 0 }
          (Resource.call_resources-['requests']).map(&:to_sym).each { |r| d[r] = 0 }
          d
        end
    end

    def other_time_resources
      @@other_time_resources ||= Resource.time_resources.map(&:to_sym) - [:total_time, :gc_time]
    end

    def other_time
      @info[:total_time] - other_time_resources.inject(0.0){|s,r| s += @info[r]}
    end

    def process(entry)
      entry.each do |line|
        # puts "matching line #{line}"
        matchers.each do |matcher|
          if extracted_values = matcher.call(line)
            # puts "merging #{extracted_values.inspect}"
            @info.merge! extracted_values
            break
          end
        end
      end
    end
  end
end


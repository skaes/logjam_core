module Logjam

  class Minutes
    def initialize(db, resources, pattern)
      @database = db
      @collection = @database["minutes"]
      @resources = resources
      @resources = [] if @resources == ["requests"]
      @pattern = pattern
      @pattern = "all_pages" if @pattern.blank? || @pattern == "::"
      @pattern = "^::#{@pattern}" if page_names.include?("::#{pattern}")
      @pattern = Regexp.new(/#{@pattern}/) unless @pattern == "all_pages" || page_names.include?(@pattern)
    end

    def page_names
      @page_names ||= Totals.new(@database).page_names
    end

    def minutes(time_slice=5)
      sums = {}
      if @resources.empty?
        counts = Hash.new(0)
      else
        counts = {}
      end
      logger.debug "pattern: #{@pattern}, resources: #{@resources.inspect}"
      n = 0
      selector = {:page => @pattern}
      fields = {:fields => ["minute","count"].concat(@resources)}
      access_time = Benchmark.realtime do
        @collection.find(selector, fields.clone).each do |row|
          n += 1
          count = row["count"]
          minute = row["minute"] / time_slice
          if @resources.empty?
            counts[minute] += count
          else
            count_sofar = counts[minute] ||= Hash.new(0)
            sum_sofar = sums[minute] ||= Hash.new(0.0)
            @resources.each do |f|
              v = row[f].to_f
              v /= 40 if f == "allocated_bytes" # HACK!!!
              sum_sofar[f] += v
              count_sofar[f] += count
            end
          end
        end
      end
      result = []
      minute_str = "minute#{time_slice}"
      if @resources.empty?
        counts.each do |m, num_requests|
          result << { minute_str => m, "requests" => num_requests}
        end
      else
        sums.each do |m,r|
          cnt = counts[m]
          r.each_key do |f|
            r[f] /= cnt[f]
          end
          result << r.merge!(minute_str => m)
        end
      end
      logger.debug "MONGO Minutes(#{selector.inspect},#{fields.inspect}) ==> #{n} records, size #{result.size}, #{"%.5f" % (access_time)} seconds}"
      result
    end

    def logger
      self.class.logger
    end

    def self.logger
      Rails.logger
    end
  end

end

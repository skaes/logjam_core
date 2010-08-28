module Logjam

  class Minutes
    attr_reader :counts, :minutes

    def initialize(db, resources, pattern, interval=5)
      @database = db
      @collection = @database["minutes"]
      @resources = resources
      @pattern = pattern
      @pattern = "all_pages" if @pattern.blank? || @pattern == "::"
      @pattern = "^::#{@pattern}" if page_names.include?("::#{pattern}")
      @pattern = Regexp.new(/#{@pattern}/) unless @pattern == "all_pages" || page_names.include?(@pattern)
      compute(interval)
    end

    def page_names
      @page_names ||= Totals.new(@database).page_names
    end

    private

    def compute(interval)
      logger.debug "pattern: #{@pattern}, resources: #{@resources.inspect}"
      minute_str = "minute#{interval}"
      sums = {}
      counts = Hash.new(0.0)
      max_sum = 0
      n = 0
      selector = {:page => @pattern}
      fields = {:fields => ["minute","count"].concat(@resources)}

      access_time = Benchmark.realtime do
        @collection.find(selector, fields.clone).each do |row|
          n += 1
          count = row["count"]
          slot = row["minute"] / interval
          counts[slot] += count
          sum_sofar = (sums[slot] ||= Hash.new(0.0))
          @resources.each do |f|
            v = row[f].to_f
            v /= 40 if f == "allocated_bytes" # HACK!!!
            sum_sofar[f] += v
          end
        end
      end

      @minutes = sums
      sums.each do |m,r|
        cnt = counts[m]
        r.each_key { |f| r[f] /= cnt }
      end

      @counts = counts
      counts.each_key { |m| counts[m] /= interval.to_f }

      logger.debug "MONGO Minutes(#{selector.inspect},#{fields.inspect}) ==> #{n} records, size #{@minutes.size}, #{"%.5f" % (access_time)} seconds}"
    end

    def logger
      self.class.logger
    end

    def self.logger
      Rails.logger
    end
  end

end

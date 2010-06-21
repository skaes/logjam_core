class Minutes
  def initialize(resources, pattern)
    @database = MONGODB.db("logjam")
    @collection = @database["minutes"]
    @resources = resources
    @pattern = pattern
    @pattern = "all_pages" if @pattern.blank?
    @pattern = Regexp.new(/#{@pattern}/) unless @pattern == "all_pages"
  end

  def minutes
    sums = {}
    counts = {}
    logger.debug "pattern: #{@pattern}, resources: #{@resources.inspect}"
    n = 0
    access_time = Benchmark.realtime do
      @collection.find({:page => @pattern}, {:fields => ["minute","count"].concat(@resources)}).each do |row|
        n += 1
        count = row["count"]
        minute = row["minute"]
        sum_sofar = sums[minute] ||= Hash.new(0.0)
        count_sofar = counts[minute] ||= Hash.new(0)
        @resources.each do |f|
          v = row[f].to_f
          sum_sofar[f] += v
          count_sofar[f] += count
        end
      end
    end
    result = []
    sums.each do |m,r|
      cnt = counts[m]
      r.each_key do |f|
        r[f] /= cnt[f]
      end
      result << r.merge!("minute5" => m)
    end
    logger.debug "MONGO minutes: #{n} records for #{@pattern}, size #{result.size}, #{"%.5f" % (access_time)} seconds}"
    result
  end

  def logger
    self.class.logger
  end

  def self.logger
    Rails.logger
  end
end

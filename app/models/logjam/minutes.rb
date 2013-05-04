module Logjam

  class Minutes

    def self.ensure_indexes(collection)
      ms = Benchmark.ms do
        collection.create_index([ ["page", Mongo::ASCENDING], ["minute", Mongo::ASCENDING] ], :background => true)
      end
      logger.debug "MONGO Minutes Indexes Creation: #{"%.1f" % (ms)} ms"
      collection
    end

    attr_reader :counts, :minutes

    def initialize(db, resources, pattern, page_names, interval=5)
      @database = db
      @collection = @database["minutes"]
      @resources = resources
      @pattern = pattern
      @pattern = "all_pages" if @pattern.blank? || @pattern == "::"
      @pattern = "^::#{@pattern}" if page_names.include?("::#{pattern}")
      @pattern = Regexp.new(/#{@pattern}/) unless @pattern == "all_pages" || page_names.include?(@pattern)
      compute(interval)
    end

    private

    def compute(interval)
      logger.debug "pattern: #{@pattern}, resources: #{@resources.inspect}"
      selector = {:page => @pattern}
      fields = {:fields => ["minute","count"].concat(@resources)}

      rows = nil
      query = "Minutes.find(#{selector.inspect},#{fields.inspect})"
      ActiveSupport::Notifications.instrument("mongo.logjam", :query => query) do |payload|
        rows = @collection.find(selector, fields.clone).to_a
        payload[:rows] = rows.size
      end

      sums = {}
      counts = Hash.new(0.0)
      while row = rows.shift
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

      @minutes = sums
      sums.each do |m,r|
        cnt = counts[m]
        r.each_key { |f| r[f] /= cnt }
      end

      @counts = counts
      counts.each_key { |m| counts[m] /= interval.to_f }

      logger.debug "MONGO Minutes size #{@minutes.size}"
    end

    def logger
      self.class.logger
    end

    def self.logger
      Rails.logger
    end
  end

end

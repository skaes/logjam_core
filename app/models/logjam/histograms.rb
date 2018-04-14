module Logjam

  class Histograms < MongoModel

    def self.ensure_indexes(collection, options = {})
      ms = Benchmark.ms do
        fields = { "page" => 1, "minute" => 1 }
        collection.indexes.create_one(fields, options)
      end
      logger.debug "MONGO Quants Indexes Creation: #{"%.1f" % (ms)} ms"
      collection
    end

    def self.empty_histograms(size: 22)
      Hash.new { |h,k| h[k] = Array.new(size, 0) }
    end

    def initialize(db, resource, pattern)
      super(db, "histograms")
      @pattern = pattern
      @pattern = "all_pages" if @pattern.blank? || @pattern == '::'
      @pattern = Regexp.new(/#{@pattern}/) unless @pattern == "all_pages"
      @resource = resource
      compute
    end

    def histograms(interval)
      return @histograms if @histograms.empty?
      max_minute = @histograms.keys.max
      max_bucket_index = @histograms.values.map do |buckets|
        buckets.map.with_index{|v,i| v > 0 ? i : nil}.compact.max
      end.max
      result = self.class.empty_histograms(size: max_bucket_index+1)
      (0..max_minute).each do |i|
        h = result[i / interval]
        @histograms[i].each_with_index{ |v,j| h[j] += v if v > 0}
      end
      result
    end

    def count
      selector = { :page => @pattern, :resource => @resource }
      query, log = build_query("Histograms.count", selector)
      with_conditional_caching(query) do |payload|
        payload[:rows] = 1
        @collection.find(selector).count
      end
    end

    private

    def compute
      selector = { :page => @pattern, :resource => @resource }
      fields = { :projection => _fields(["minute", "resource", "histogram"])}
      query, log = build_query("Histograms.find", selector, fields)
      rows = with_conditional_caching(log) do |payload|
        rs = []
        query.each do |row|
          row.delete("_id")
          rs << row
        end
        payload[:rows] = rs.size
        rs
      end

      histograms = @histograms = self.class.empty_histograms
      while row = rows.shift
        histogram = histograms[row["minute"]]
        row["histogram"].each_with_index{ |v,j| histogram[j] += v }
      end

      # logger.debug("HISTOGRAMS(#{@pattern.inspect}): #{@histograms.inspect}")
    end

  end

end

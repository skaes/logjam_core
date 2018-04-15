module Logjam

  class Histograms < MongoModel

    def self.empty_histograms(size: 22)
      Hash.new { |h,k| h[k] = Array.new(size, 0) }
    end

    def initialize(db, resources, pattern)
      super(db, "histograms")
      @pattern = pattern
      @pattern = "all_pages" if @pattern.blank? || @pattern == '::'
      @is_a_module = modules.include?("::#{pattern}")
      @is_a_page = page_names.include?(pattern)
      @ignore_modules = false
      if @is_a_page
        # no need to change pattern
      elsif @is_a_module
        @pattern = "::#{@pattern}"
      else
        @ignore_modules = true
        @pattern = Regexp.new(/#{@pattern}/)
      end
      @resources = resources
      compute
    end

    def histograms(interval)
      return @histograms if @histograms.empty?
      histograms_for_resource = Hash.new { |h,r| h[r] = {} }
      @histograms.each do |resource, histograms|
        max_minute = histograms.keys.max
        max_bucket_index = histograms.values.map do |buckets|
          buckets.map.with_index{|v,i| v > 0 ? i : nil}.compact.max
        end.max
        folded_histograms = self.class.empty_histograms(size: max_bucket_index+1)
        histograms_for_resource[resource] = folded_histograms
        (0..max_minute).each do |i|
          h = folded_histograms[i / interval]
          histograms[i].each_with_index{ |v,j| h[j] += v if v > 0}
        end
      end
      histograms_for_resource
    end

    def count
      selector = { :page => @pattern } #, :resource => { '$in' => @resources } }
      query, log = build_query("Histograms.count", selector)
      with_conditional_caching(query) do |payload|
        payload[:rows] = 1
        @collection.find(selector).count
      end
    end

    def page_names
      @page_names ||=
        begin
          query = "Histograms.distinct(:page)"
          with_conditional_caching(query) do |payload|
            rows = @collection.find.distinct(:page)
            payload[:rows] = rows.size
            rows.to_a
          end
        end
    end

    def modules
      page_names.grep(/^::/)
    end

    private

    def compute
      selector = { :page => @pattern } #, :resource => { '$in' => @resources } }
      fields = { :projection => _fields(["page", "minute", "resource", "histogram"])}
      query, log = build_query("Histograms.find", selector, fields)
      rows = with_conditional_caching(log) do |payload|
        rs = []
        query.each do |row|
          row.delete("_id")
          page = row.delete("page")
          next if @ignore_modules && page.starts_with?("::")
          rs << row
        end
        payload[:rows] = rs.size
        rs
      end

      histograms = @histograms = Hash.new {|h,r| h[r] = self.class.empty_histograms }
      while row = rows.shift
        histogram = histograms[row["resource"]][row["minute"]]
        row["histogram"].each_with_index{ |v,j| histogram[j] += v }
      end

      # logger.debug("HISTOGRAMS(#{@pattern.inspect}): #{@histograms.inspect}")
    end

  end

end

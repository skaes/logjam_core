module Logjam

  class Total
    attr_writer :page_info
    attr_reader :resources

    def initialize(page_info, resources)
      @page_info = page_info
      @resources = resources
    end

    def page
      @page_info["page"]
    end

    def page=(page)
      @page_info["page"] = page
    end

    def count(resource=nil)
      @page_info["count"]
    end

    def sum(resource)
      @page_info[resource] || 0
    end

    def sum_sq(resource)
      @page_info["#{resource}_sq"] || 0.0
    end

    def avg(resource)
      sum(resource) / count.to_f
    end

    def stddev(resource)
      @page_info["#{resource}_stddev"] ||=
        begin
          n, s, sq = count, sum(resource), sum_sq(resource)
          a = avg(resource)
          (n == 1 || s == 0) ? 0.0 : Math.sqrt((sq - n*a*a).abs/(n-1).to_f)
        end
    end

    def apdex
      @page_info["apdex"]
    end

    def apdex_score
      (apdex["satisfied"].to_f + apdex["tolerating"].to_f / 2.0) / count.to_f
    end

    def response
      @page_info["response"]
    end

    def severity
      @page_info["severity"]
    end

    def error_count
      response["500"].to_i
    end

    def add(other)
      @page_info["count"] += other.count
      @resources.each do |r|
        @page_info[r] = sum(r) + other.sum(r)
        @page_info["#{r}_sq"] = sum_sq(r) + other.sum_sq(r)
      end
      if apdex
        other.apdex.each {|x,y| apdex[x] = (apdex[x]||0) + y}
      end
      if response
        other.response.each {|x,y| response[x] = (response[x]||0) + y}
      end
      if severity
        other.severity.each {|x,y| severity[x] = (severity[x]||0) + y}
      end
    end

    def clone
      res = super
      res.page_info = pi = @page_info.clone
      pi["apdex"] = pi["apdex"].clone if pi["apdex"]
      pi["response"] = pi["response"].clone if pi["response"]
      pi["severity"] = pi["severity"].clone if pi["severity"]
      @resources.each do |r|
        pi.delete("#{r}_avg")
        pi.delete("#{r}_stddev")
      end
      res
    end
  end

  class Totals

    def self.ensure_indexes(collection)
      ms = Benchmark.ms do
        collection.create_index("page", :background => true)
      end
      logger.debug "MONGO Totals Indexes Creation: #{"%.1f" % (ms)} ms"
      collection
    end

    attr_reader :resources, :pattern, :pages

    def initialize(db, resources=[], pattern='')
      @database = db
      @collection = @database["totals"]
      @resources = resources.dup
      @apdex = @resources.delete("apdex")
      @response = @resources.delete("response")
      @severity = @resources.delete("severity")
      @pattern = pattern
      @sum = {}
      @avg = {}
      @sum_sq = {}
      @stddev = {}
    end

    def the_pages
      @pages ||= compute
    end

    def page_names
      @page_names ||= @collection.distinct(:page)
    end

    def pages(options)
      order = options[:order] || :sum
      limit = options[:limit] || 1000
      if order.to_sym == :count
        pages = the_pages.sort_by{|r| -r.count}
      else
        raise "unknown sort method" unless order =~ /^(.+)_(sum|avg|stddev)$/
        resource, function = $1, $2
        pages = the_pages.sort_by{|r| -r.send(function, resource)}
      end
      return pages if pages.size <= limit
      proper, rest = pages[0..limit-2], pages[limit-1..-1]
      proper << combine_pages(rest)
    end

    def count
      @count ||= the_pages.inject(0){|n,p| n += p.count}
    end

    def sum(resource)
      @sum[resource] ||= the_pages.inject(0.0){|n,p| n += p.sum(resource)}
    end

    def sum_sq(resource)
      @sum_sq[resource] ||= the_pages.inject(0.0){|n,p| n += p.sum_sq(resource)}
    end

    def avg(resource)
      @avg[resource] ||= sum(resource)/count rescue 0.0
    end

    def stddev(resource)
      @stddev[resource] ||=
        begin
          n, s, sq = count, sum(resource), sum_sq(resource)
          a = avg(resource)
          (n == 1 || s == 0) ? 0.0 : Math.sqrt((sq - n*a*a).abs/(n-1).to_f)
        end
    end

    def apdex
      @apdex_hash ||= the_pages.inject(Hash.new(0)){|h,p| p.apdex.each{|k,v| h[k] += v}; h}
    end

    def response_codes
      @response_hash ||= the_pages.inject(Hash.new(0)){|h,p| p.response.each{|k,v| h[k.to_i] += v.to_i}; h}
    end

    def severities
      @severity_hash ||= the_pages.inject(Hash.new(0)){|h,p| p.severity.each{|k,v| h[k.to_i] += v.to_i}; h}
    end

    protected

    def selector
      case
      when pattern == '' then {:page => /\#/}
      when page_names.include?(pattern) then {:page => pattern}
      when page_names.grep(/^#{pattern}/).size > 0 then {:page => /^#{pattern}/}
      else {:page => /#{pattern}/}
      end
    end

    def compute
      all_fields = ["page", "count", @apdex, @response, @severity].compact + @resources
      sq_fields = @resources.map{|r| "#{r}_sq"}
      fields = {:fields => all_fields.concat(sq_fields)}

      rows = nil
      access_time = Benchmark.ms { rows = @collection.find(selector, fields.clone).to_a }
      logger.debug "MONGO Totals.find(#{selector.inspect},#{fields.inspect}) ==> #{rows.size} records, #{"%.1f" % (access_time)} ms"

      result = []
      while row = rows.shift
        result << Total.new(row, @resources)
      end
      # logger.debug result.inspect
      result
    end

    def combine_pages(pages)
      combined = pages.shift.clone
      combined.page = "Others..."
      pages.each {|page| combined.add(page)}
      combined
    end

    def logger
      self.class.logger
    end

    def self.logger
      Rails.logger
    end
  end
end

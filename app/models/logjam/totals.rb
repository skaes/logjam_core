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
      @page_info["apdex"] ||= {}
    end

    def apdex_score
      (apdex["satisfied"].to_f + apdex["tolerating"].to_f / 2.0) / count.to_f
    end

    def response
      @page_info["response"] ||= {}
    end

    def severity
      @page_info["severity"] ||= {}
    end

    def exceptions
      @page_info["exceptions"] ||= {}
    end

    def exception_count
      exceptions.values.inject(0){|s,v| s += v.to_i}
    end

    def error_count
      # response["500"].to_i
      severity["3"].to_i + severity["4"].to_i
    end

    def warning_count
      severity["2"].to_i
    end

    def four_hundreds
      n = 0
      response.each_pair{|k,v| n += v.to_i if k =~ /^4/}
      n
    end

    def add(other)
      @page_info["count"] += other.count
      @resources.each do |r|
        @page_info[r] = sum(r) + other.sum(r)
        @page_info["#{r}_sq"] = sum_sq(r) + other.sum_sq(r)
      end
      other.apdex.each {|x,y| apdex[x] = (apdex[x]||0) + y}
      other.response.each {|x,y| response[x] = (response[x]||0) + y}
      other.severity.each {|x,y| severity[x] = (severity[x]||0) + y}
      other.exceptions.each {|x,y| exceptions[x] = (exceptions[x]||0) + y}
    end

    def clone
      res = super
      res.page_info = pi = @page_info.clone
      pi["apdex"] = pi["apdex"].clone if pi["apdex"]
      pi["response"] = pi["response"].clone if pi["response"]
      pi["severity"] = pi["severity"].clone if pi["severity"]
      pi["exceptions"] = pi["exceptions"].clone if pi["exceptions"]
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

    def self.update_severities(db)
      totals = db["totals"]
      pages = totals.distinct(:page)
      pages.each do |page|
        severities = {}
        [2, 3, 4].each do |severity|
          requests = Requests.new(db, nil, page, :severity => severity)
          num_requests = requests.count(:severity => severity)
          severities["severity.#{severity}"] = num_requests if num_requests > 0
        end
        unless severities.empty?
          puts "#{page}, #{severities.inspect}"
          totals.update({:page => page}, {'$set' => severities}, {:upsert => false, :multi => false})
        end
      end
    end

    attr_reader :resources, :pattern, :pages

    def initialize(db, resources=[], pattern='', page_name_list=nil)
      @database = db
      @collection = @database["totals"]
      @resources = resources.dup
      @apdex = @resources.delete("apdex")
      @response = @resources.delete("response")
      @severity = @resources.delete("severity")
      @exceptions = @resources.delete("exceptions")
      @pattern = pattern
      @page_names = page_name_list
      @sum = {}
      @avg = {}
      @sum_sq = {}
      @stddev = {}
    end

    def the_pages
      @pages ||= compute
    end

    def page_names
      @page_names ||=
        begin
          query = "Totals.distinct(:page)"
          ActiveSupport::Notifications.instrument("mongo.logjam", :query => query) do |payload|
            rows = @collection.distinct(:page)
            payload[:rows] = rows.size
            rows
          end
        end
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

    def request_count
      @request_count ||=
        begin
          query = "Totals.request_count"
          ActiveSupport::Notifications.instrument("mongo.logjam", :query => query) do |payload|
            rows = @collection.find({:page=>"all_pages"},{:fields=>["count"]}).to_a
            payload[:rows] = rows.size
            rows.first["count"].to_i
          end
        end
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

    def zero_resources?(resources)
      resources.all?{|r| avg(r) == 0}
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

    def exceptions
      @exceptions_hash ||= the_pages.inject(Hash.new(0)){|h,p| p.exceptions.each{|k,v| h[k] += v.to_i}; h}
    end

    def exception_count
      @exception_count ||= exceptions.values.inject(0){|s,v| s += v}
    end

    protected

    def selector
      case
      when pattern.blank? then {:page => /\#/}
      when page_names.include?(pattern) then {:page => pattern}
      when page_names.grep(/^#{pattern}/).size > 0 then {:page => /^#{pattern}/}
      else {:page => /#{pattern}/}
      end
    end

    def compute
      all_fields = ["page", "count", @apdex, @response, @severity, @exceptions].compact + @resources
      sq_fields = @resources.map{|r| "#{r}_sq"}
      fields = {:fields => all_fields.concat(sq_fields)}

      rows = nil
      query = "Totals.find(#{selector.inspect},#{fields.inspect})"
      ActiveSupport::Notifications.instrument("mongo.logjam", :query => query) do |payload|
        rows = @collection.find(selector, fields.clone).to_a
        payload[:rows] = rows.size
      end

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

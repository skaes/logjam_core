# -*- coding: utf-8 -*-
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

    def js_exceptions
      @page_info["js_exceptions"] ||= {}
    end

    def js_exception_count
      js_exceptions.values.inject(0){|s,v| s += v.to_i}
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

    def callers
      @page_info["callers"] ||= {}
    end

    def callers_count
      callers.values.inject(0){|s,v| s += v.to_i}
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
      other.callers.each {|x,y| callers[x] = (callers[x]||0) + y}
      other.js_exceptions.each {|x,y| js_exceptions[x] = (js_exceptions[x]||0) + y}
    end

    def clone
      res = super
      res.page_info = pi = @page_info.clone
      pi["apdex"] = pi["apdex"].clone if pi["apdex"]
      pi["response"] = pi["response"].clone if pi["response"]
      pi["severity"] = pi["severity"].clone if pi["severity"]
      pi["exceptions"] = pi["exceptions"].clone if pi["exceptions"]
      pi["callers"] = pi["callers"].clone if pi["callers"]
      pi["js_exceptions"] = pi["js_exceptions"].clone if pi["js_exceptions"]
      @resources.each do |r|
        pi.delete("#{r}_avg")
        pi.delete("#{r}_stddev")
      end
      res
    end

    def to_hash
      {
        page: page,
        count: count,
        apdex: apdex.merge(t: 0.5, score: apdex_score),
        response_codes: response,
      }.tap do |h|
        h[:exceptions] = exceptions unless exceptions.empty?
        h[:js_exceptions] = js_exceptions unless js_exceptions.empty?
        h[:log_severities] = severity unless severity.empty?
        hr = h[:resources] = {}
        resources.each do |r|
          unless (s = sum(r)) == 0
            hr[r] = { sum: s, avg: avg(r), stddev: stddev(r) }
          end
        end
      end
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

    def self.call_relationships(db, app)
      totals = db["totals"]
      rows = []
      ActiveSupport::Notifications.instrument("mongo.logjam", :query => "Totals.call_relationships()") do |payload|
        rows = totals.find({:page => /#/}, :fields => %w(page callers)).to_a
        payload[:rows] = rows.size
      end
      rows.each_with_object({}) do |r,o|
        callers = r['callers']
        page = r['page']
        o["#{app}-#{page}"] = callers unless callers.blank? || page !~ /#/
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
      @callers = @resources.delete("callers")
      @js_exceptions = @resources.delete("js_exceptions")
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
            rows = @collection.distinct(:page, :count => {'$gt' => 0})
            payload[:rows] = rows.size
            rows
          end
        end
    end

    def collected_resources
      @collected_resources ||=
        begin
          query = "Totals.find({page:'all_pages'})"
          row = nil
          ActiveSupport::Notifications.instrument("mongo.logjam", :query => query) do |payload|
            payload[:rows] = 1
            row = @collection.find_one({:page => 'all_pages'},{})
          end
          row ? row.keys & Requests::FIELDS : Requests::FIELDS
        end
    end

    def pages(options)
      limit = options[:limit] || 1000
      filter = options[:filter]
      pages = self.the_pages
      pages.reject!{|p| !filter.call(p.page)} if filter
      if order = options[:order]
        case order.to_sym
        when :count
          pages.sort_by!{|r| -r.count}
        when :apdex
          pages.sort_by!{|r| r.apdex_score}
        else
          raise "unknown sort method: #{order}" unless order.to_s =~ /^(.+)_(sum|avg|stddev)$/
          resource, function = $1, $2
          pages.sort_by!{|r| -r.send(function, resource)}
        end
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

    def callers
      # callers unfortunately have dots in their names
      @callers_hash ||= the_pages.inject(Hash.new(0)){|h,p| p.callers.each{|k,v| h[k.gsub('∙','.')] += v.to_i}; h}
    end

    def callers_count
      @callers_count ||= callers.values.inject(0){|s,v| s += v}
    end

    def js_exceptions
      @js_exceptions_hash ||= the_pages.inject(Hash.new(0)){|h,p| p.js_exceptions.each{|k,v| h[k] += v.to_i}; h}
    end

    def js_exception_count
      @js_exception_count ||= js_exceptions.values.inject(0){|s,v| s += v}
    end

    protected

    def selector
      case
      when pattern.blank? then {:page => /\#/}
      when page_names.include?(pattern) then {:page => pattern}
      when page_names.grep(/^#{pattern}/).size > 0 then {:page => /^#{pattern}/}
      else {:page => /#{pattern}/}
      end.merge!(:count => {'$gt' => 0})
    end

    def compute
      all_fields = ["page", "count", @apdex, @response, @severity, @exceptions, @js_exceptions, @callers].compact + @resources
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

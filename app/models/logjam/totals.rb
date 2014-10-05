# -*- coding: utf-8 -*-
module Logjam

  class Total
    attr_writer :page_info
    attr_reader :resources

    def initialize(page_info, resources)
      @page_info = page_info
      @page_info["count"] ||= 0
      @page_info["page_count"] ||= 0
      @page_info["ajax_count"] ||= 0
      @page_info["frontend_count"] ||= 0
      @resources = resources
    end

    def page
      @page_info["page"]
    end

    def page=(page)
      @page_info["page"] = page
    end

    FE_RESOURCE_TYPES = %i(frontend dom)

    def backend_count; @page_info["count"]; end
    def frontend_count; @page_info["frontend_count"]; end
    def ajax_count; @page_info["ajax_count"]; end
    def page_count; @page_info["page_count"]; end

    def count(resource="total_time")
      if resource == "ajax_time"
        ajax_count
      elsif resource == "frontend_time"
        frontend_count
      elsif FE_RESOURCE_TYPES.include?(Resource.resource_type(resource))
        page_count
      elsif resource == :frontend
        frontend_count
      else
        backend_count
      end
    end

    def sum(resource)
      @page_info[resource] || 0
    end

    def sum_sq(resource)
      @page_info["#{resource}_sq"] || 0.0
    end

    def avg(resource)
      sum(resource) / count(resource).to_f
    end

    def stddev(resource)
      @page_info["#{resource}_stddev"] ||=
        begin
          n, s, sq = count(resource), sum(resource), sum_sq(resource)
          a = avg(resource)
          (n == 1 || s == 0) ? 0.0 : Math.sqrt((sq - n*a*a).abs/(n-1).to_f)
        end
    end

    def apdex(section = :backend)
      if section == :backend
        @page_info["apdex"] ||= {}
      else
        @page_info["fapdex"] ||= {}
      end
    end

    def fapdex; apdex(:frontend); end

    def apdex_score(section = :backend)
      (apdex(section)["satisfied"].to_f + apdex(section)["tolerating"].to_f / 2.0) / count(section).to_f
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
      @page_info["count"] += other.backend_count
      @page_info["page_count"] += other.page_count
      @page_info["ajax_count"] += other.ajax_count
      @page_info["frontend_count"] += other.frontend_count
      @resources.each do |r|
        begin
          @page_info[r] = sum(r) + other.sum(r)
          @page_info["#{r}_sq"] = sum_sq(r) + other.sum_sq(r)
        rescue
          Rails.logger.error("MUUUU[#{r}]: #{@page_info.inspect}, !!! #{sum(r)}  !!! #{other.send :inspect}")
          raise
        end
      end
      other.apdex.each {|x,y| apdex[x] = (apdex[x]||0) + y}
      other.fapdex.each {|x,y| fapdex[x] = (fapdex[x]||0) + y}
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
      pi["fapdex"] = pi["fapdex"].clone if pi["fapdex"]
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
        count: count('total_time'),
        apdex: apdex.merge(t: 0.5, score: apdex_score),
        response_codes: response,
      }.tap do |h|
        h[:exceptions] = exceptions unless exceptions.empty?
        h[:js_exceptions] = js_exceptions unless js_exceptions.empty?
        h[:log_severities] = human_severities(severity) unless severity.empty?
        hr = h[:resources] = {}
        resources.each do |r|
          unless (s = sum(r)) == 0
            hr[r] = { sum: s, avg: avg(r), stddev: stddev(r) }
          end
        end
      end
    end

    private
    SEVERITY_LABELS = %w(debug info warn error fatal)
    def human_severities(severities)
      # puts severities.inspect
      severities.each_with_object({}){|(l,c),h| h[SEVERITY_LABELS[l.to_i]] = c}
    end
  end

  class Totals < MongoModel

    def self.ensure_indexes(collection)
      ms = Benchmark.ms do
        collection.create_index("page", :background => true)
      end
      logger.debug "MONGO Totals Indexes Creation: #{"%.1f" % (ms)} ms"
      collection
    end

    attr_reader :resources, :pattern, :pages

    def initialize(db, resources=[], pattern='', page_name_list=nil)
      super(db, "totals")
      @resources = resources.dup
      @apdex = @resources.delete("apdex")
      @fapdex = @resources.delete("fapdex")
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
      @count = {}
      @apdex_hash = {}
    end

    def the_pages
      @pages ||= compute
    end

    def page_names
      @page_names ||=
        begin
          query = "Totals.distinct(:page)"
          with_conditional_caching(query) do |payload|
            rows = @collection.distinct(:page, :count => {'$gt' => 0})
            payload[:rows] = rows.size
            rows
          end
        end
    end

    def collected_resources
      @collected_resources ||=
        begin
          query = "Totals.find({page:'all_pages'},{})"
          row = with_conditional_caching(query) do |payload|
                  r = @collection.find_one({:page => 'all_pages'},{})
                  payload[:rows] = r ? 1 : 0
                  r.delete("_id") if r
                  r
                end
          row ? row.keys & Requests::FIELDS : Requests::FIELDS
        end
    end

    def pages(options)
      section = options[:section] || :backend
      limit = options[:limit] || 1000
      filter = options[:filter]
      pages = self.the_pages.clone
      pages.reject!{|p| !filter.call(p.page)} if filter
      if order = options[:order]
        case order.to_sym
        when :count
          pages.sort_by!{|r| -r.count('total_time')}
        when :apdex
          pages.sort_by!{|r| v = r.apdex_score(section); v.nan? ? 1.1 : v}
        else
          raise "unknown sort method: #{order}" unless order.to_s =~ /^(.+)_(sum|avg|stddev)$/
          resource, function = $1, $2
          pages.sort_by!{|r| v = r.send(function, resource); v.is_a?(Float) && v.nan? ? 0 : -v}
        end
      end
      return pages if pages.size <= limit
      return combine_pages(pages) if limit == 1
      proper, rest = pages[0..limit-2], pages[limit-1..-1]
      proper << combine_pages(rest)
    end

    def count(resource = 'total_time')
      @count[resource] ||= the_pages.inject(0){|n,p| n += p.count(resource)}
    end

    def actions
      page = pattern.to_s.sub(/\A::/,'')
      match =
        case
        when page.is_a?(Regexp) then page
        when page.blank? then /\#/
        when page_names.include?(page) then /^#{page}$/
        when page_names.grep(/^#{page}/).size > 0 then /^#{page}/
        else /#{page}/
        end
      page_names.select{|p| p =~ match }
    end

    KNOWN_SECTIONS = %i(backend frontend)
    def request_count(section = :backend)
      raise ArgumentErrror.new("unknown section: #{section}") unless KNOWN_SECTIONS.include?(section)
      unless @request_counts
        fields = %w(count page_count ajax_count frontend_count)
        query = "Totals.request_count(#{fields.join(',')})"
        @request_counts = with_conditional_caching(query) do |payload|
          counts = Hash.new(0)
          rows = @collection.find({:page=>"all_pages"},{:fields=>fields}).to_a
          payload[:rows] = rows.size
          if rows.size > 0
            counts[:backend] = rows.first["count"].to_i
            counts[:frontend] = rows.first["frontend_count"].to_i
            counts[:ajax] = rows.first["ajax_count"].to_i
            counts[:page] = rows.first["page_count"].to_i
          end
          counts
        end
      end
      @request_counts[section]
    end

    def sum(resource)
      @sum[resource] ||= the_pages.inject(0.0){|n,p| n += p.sum(resource)}
    end

    def sum_sq(resource)
      @sum_sq[resource] ||= the_pages.inject(0.0){|n,p| n += p.sum_sq(resource)}
    end

    def avg(resource)
      @avg[resource] ||= sum(resource)/count(resource) rescue 0.0
    end

    def zero_resources?(resources)
      resources.all?{|r| avg(r) == 0}
    end

    def stddev(resource)
      @stddev[resource] ||=
        begin
          n, s, sq = count(resource), sum(resource), sum_sq(resource)
          a = avg(resource)
          (n == 1 || s == 0) ? 0.0 : Math.sqrt((sq - n*a*a).abs/(n-1).to_f)
        end
    end

    def apdex(section = :backend)
      @apdex_hash[section] ||= the_pages.inject(Hash.new(0)){|h,p| p.apdex(section).each{|k,v| h[k] += v}; h}
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

    def call_relationships(app)
      query = "Totals.call_relationships()"
      rows = with_conditional_caching(query) do |payload|
        rs = @collection.find({:page => /#/}, :fields => %w(page callers)).to_a
        payload[:rows] = rs.size
        rs.each{|r| r.delete("_id")}
        rs
      end
      rows.each_with_object({}) do |r,o|
        callers = r['callers']
        page = r['page']
        o["#{app}-#{page}"] = callers unless callers.blank? || page !~ /#/
      end
    end

    def happy_count(section = :backend)
      apdex(section)["happy"].to_i
    end

    def happy(section = :backend)
      happy_count(section) / count(section).to_f
    end

    def satisfied_count(section = :backend)
      apdex(section)["satisfied"].to_i
    end

    def satisfied(section = :backend)
      satisfied_count(section) / count(section).to_f
    end

    def tolerating_count(section = :backend)
      apdex(section)["tolerating"].to_i
    end

    def tolerating(section = :backend)
      tolerating_count(section) / count(section).to_f
    end

    def frustrated_count(section = :backend)
      apdex(section)["frustrated"].to_i
    end

    def frustrated(section = :backend)
      frustrated_count(section) / count(section).to_f
    end

    def apdex_score(section = :backend)
      satisfied(section) + tolerating(section) / 2.0
    end

    protected

    def selector
      case
      when pattern.is_a?(Regexp) then {:page => pattern}
      when pattern.blank? then {:page => /\#/}
      when page_names.include?(pattern) then {:page => pattern}
      when page_names.grep(/^#{pattern}/).size > 0 then {:page => /^#{pattern}/}
      else {:page => /#{pattern}/}
      end.merge!(:count => {'$gt' => 0})
    end

    def compute
      all_fields = ["page", "count", "page_count", "ajax_count", "frontend_count", @apdex, @fapdex, @response, @severity, @exceptions, @js_exceptions, @callers].compact + @resources
      sq_fields = @resources.map{|r| "#{r}_sq"}
      fields = {:fields => all_fields.concat(sq_fields)}

      query = "Totals.find(#{selector.inspect},#{fields.inspect})"
      rows = with_conditional_caching(query) do |payload|
        rs = @collection.find(selector, fields.clone).to_a
        payload[:rows] = rs.size
        rs.each{|r| r.delete("_id")}
        rs
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

  end
end

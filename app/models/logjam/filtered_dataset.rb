module Logjam

  class FilteredDataset
    HEAP_SLOT_SIZE = 40

    attr_accessor :interval, :page, :response_code,
    :plot_kind, :resource, :grouping, :grouping_function,
    :start_minute, :end_minute, :date, :limit, :offset

    DEFAULTS = {:plot_kind => :time, :interval => '5', :section => 'backend',
      :grouping => 'page', :resource => 'total_time', :grouping_function => 'sum',
      :start_minute => '0', :end_minute => '1440', :page => '', :kind => 'callers'}

    def self.is_default?(attribute, value)
      DEFAULTS.keys.include?(attribute.to_sym) && DEFAULTS[attribute.to_sym].to_s == value
    end

    def self.clean_url_params(params, old_params)
      default_app = params.delete(:default_app) || Logjam.default_app
      params = params.reject{|k,v| old_params[k] == v && (v.blank? || is_default?(k, v)) }
      if app = params[:app]
        params.delete(:app) if app == default_app
        if env = params[:env]
          if default_env = params.delete(:default_env)
            params.delete(:env) if env == default_env
          else
            params.delete(:env) if env == Logjam.default_env(app)
          end
        end
      end
      params
    end

    def initialize(options = {})
      # puts options.inspect
      @date = options[:date]
      @app = options[:app]
      @env = options[:env]
      @db = Logjam.db(@date, @app, @env)
      @interval = (options[:interval] || DEFAULTS[:interval]).to_i
      @page = options[:page].to_s
      @response_code = options[:response_code] if options[:response_code].present?
      @plot_kind = options[:plot_kind] || DEFAULTS[:plot_kind]
      @resource = options[:resource] || DEFAULTS[:resource]
      @grouping = options[:grouping]
      @grouping_function = options[:grouping_function] || DEFAULTS[:grouping_function]
      @start_minute = (options[:start_minute] || DEFAULTS[:start_minute]).to_i
      @end_minute = (options[:end_minute] || DEFAULTS[:end_minute]).to_i
      @collected_resources = options[:collected_resources]
      @limit = options[:limit] || (@grouping == "request" ? 12 : 12)
      @offset = options[:offset] || 0
      @request_counts = {}
      @count = {}
      @query_result = {}
      @plot_data = {}
    end

    def grouping_name
      if grouping == "page"
        if namespaces?
          "namespace"
        else
          "action"
        end
      else
        grouping
      end
    end

    def page_description
      page == "::" ? "all actions" : page
    end

    def description
      Resource.description(resource, grouping, grouping_function)
    end

    def short_description
      Resource.short_description(resource, grouping, grouping_function)
    end

    def grouping?
      Resource.grouping?(grouping)
    end

    def hash
      Digest::MD5.hexdigest "#{date} #{interval} #{user_id} #{host} #{page} #{response_code} #{plot_kind} #{start_minute} #{end_minute}"
    end

    def accumulates_time?
      [:time, :frontend].include?(Resource.resource_type(resource)) &&
        grouping? &&
        [:sum, :avg, :max, :stddev, :count, :apdex, :fapdex, :papdex, :xapdex].include?(grouping_function.to_sym)
    end

    def intervals_per_day
      24 * 60 / interval
    end

    def intervals_per_hour
      60 / interval
    end

    def live_stream?
      page.blank? || page == "all_pages" || page == "::" || namespace?
    end

    def empty?(resource = 'total_time')
      count_requests(resource) == 0
    end

    def count_requests(section = :backend)
      @request_counts[section] ||= totals.count(section).to_i
    end

    def count(section = :backend)
      @count[section] ||= totals.request_count(section)
    end

    def sum(time_attr = 'total_time')
      totals.sum(time_attr)
    end

    def single_page?
      totals.the_pages.size == 1
    end

    def size(section = :backend)
      do_the_query(section).size
    end

    def requests
      @requests ||=
        begin
          query_opts = {start_minute: @start_minute, end_minute: @end_minute, skip: @offset, limit: @limit}
          Requests.new(@db, resource, page, query_opts).all
        end
    end

    def stored_requests
      @stored_requests ||=
        begin
          query_opts = {start_minute: @start_minute, end_minute: @end_minute}
          Requests.new(@db, resource, page, query_opts).count
        end
    end

    def do_the_query(section = :backend, options = {})
      options = {:grouping => self.grouping, :resource => self.resource}.merge!(options)
      grouping = options[:grouping]
      resource = options[:resource]
      @query_result[[section, grouping, resource]] ||=
        if grouping == "request"
          requests
        else
          if grouping_function.to_sym == :count
            sort_by = "count"
          elsif grouping_function.to_sym == :apdex
            sort_by = "apdex"
          else
            sort_by = "#{resource}_#{grouping_function}"
          end
          totals.pages(:order => sort_by, :limit => limit, :section => section, :resource =>resource)
        end
    end

    def resource_fields
      case Resource.resource_type(resource)
      when :time       then Resource.time_resources
      when :call       then Resource.call_resources
      when :memory     then Resource.memory_resources
      when :heap       then Resource.heap_resources
      when :dom        then Resource.dom_resources
      when :frontend   then Resource.frontend_resources
      end & @collected_resources
    end

    def totals
      @totals ||= Totals.new(@db, %w(apdex fapdex papdex xapdex response severity exceptions soft_exceptions js_exceptions) + resource_fields, page)
    end

    def namespace?
      totals.page_names.include?("::#{page.sub(/\A::/,'')}")
    end

    def namespaces?(section = :backend)
      totals.page_names.any?{|pn| pn =~ /\A::/}
      # TODO: this breaks apdex sorting. why?
      #pages = do_the_query(:backend, :grouping => "action")
      #pages.all?{|p| p.page == 'Others...' || p.page =~ /\A::/}
    end

    def action?
      totals.page_names.include?(page)
    end

    def top_level?
      ['', 'all_pages', '::'].include?(page)
    end

    def summary
      @summary ||=
        begin
          all_resources = Resource.time_resources + Resource.call_resources + Resource.memory_resources + Resource.heap_resources + Resource.frontend_resources + Resource.dom_resources
          resources = (all_resources & @collected_resources) - %w(heap_growth) + %w(apdex fapdex papdex xapdex response callers senders)
          Totals.new(@db, resources, page, totals.page_names)
        end
    end

    def measures_bytes?(attr)
      [:allocated_memory, :allocated_bytes].include? attr.to_sym
    end

    YLABELS = {
      :time => 'Response time (ms)', :call => '# of calls',
      :memory => 'Allocations (bytes)', :heap => 'Heap size (slots)',
      :frontend => 'Frontend time (ms)', :dom => '# of nodes'
    }

    def has_callers?
      summary.callers_count > 0
    end

    def has_senders?
      summary.senders_count > 0
    end

    def has_frontend?
      summary.request_count(:frontend) > 0
    end

    def ylabel
      YLABELS[plot_kind] || ""
    end

    RESOURCES_EXCLUDED_FROM_PLOT = %w(total_time allocated_memory requests heap_growth page_time frontend_time)
    LINE_PLOTTED_RESOURCES = %w(ajax_time gc_time dom_interactive total_time_max)

    def plotted_resources
      resources = (Resource.resources_for_type(plot_kind) & @collected_resources)
      resources << "total_time_max" if resources.include?("total_time")
      resources - RESOURCES_EXCLUDED_FROM_PLOT
    end

    def plot_data(section)
      @plot_data[section] ||=
        begin
          resources = plotted_resources
          events = Events.new(@db).events
          mins = Minutes.new(@db, resources, page, totals.page_names, interval)
          minutes = mins.minutes
          counts = section == :frontend ? mins.counts["frontend_count"] : mins.counts["count"]
          max_total = 0
          plot_resources = resources.clone
          LINE_PLOTTED_RESOURCES.each do |r|
            plot_resources += [r] if plot_resources.delete(r)
          end
          plot_resources.unshift("free_slots") if plot_resources.delete("heap_size")
          zero = Hash.new(0.0)
          results = plot_resources.inject({}){|h,r| h[r] = {}; h}
          totals = []
          nonzero = 0
          intervals_per_day.times do |i|
            row = minutes[i] || zero
            total = 0
            if (heap_size = row["heap_size"]) && (live_data_set_size = row["live_data_set_size"]) && (live_data_set_size > heap_size)
              row["live_data_set_size"] = row["heap_size"]
            end
            plot_resources.each do |r|
              v = r == "free_slots" ? row["heap_size"] - row["live_data_set_size"] : row[r]
              if v.is_a?(Float) && v.nan?
                Rails.logger.error("found NaN for resource #{r} minute #{i}")
                v = 0.0
              else
                # Rails.logger.error("found #{v} for resource #{r} minute #{i}")
              end
              total += v unless LINE_PLOTTED_RESOURCES.include?(r)
              results[r][i] = v
            end
            if total == 0 && section == :frontend && (ajax_time = row["ajax_time"])
              total = ajax_time.to_f
            end
            totals << total if total > 0
            if plot_resources.include?("total_time_max") && (v = row["total_time_max"])
              total = v if v > 0
            end
            max_total = total if max_total < total
            nonzero += 1 if total > 0
          end
          plot_data = data_for_proto_vis(results, plot_resources).reverse
          lines = {}
          LINE_PLOTTED_RESOURCES.reverse.each do |r|
            lines[r] = plot_data.shift if resources.include?(r)
          end
          request_counts = []
          intervals_per_day.times{|i| request_counts << (counts[i] || 0) / 60.0}
          y_zoom = totals.sort[(totals.size*0.9).to_i].to_f
          [plot_resources-LINE_PLOTTED_RESOURCES, plot_data, events, max_total, request_counts, lines, y_zoom]
        end
    end

    def data_for_proto_vis(results, resources)
      data = resources.map{[]}
      resources.each_with_index do |r,j|
        resource_data = data[j]
        resource_hash = results[r]
        intervals_per_day.times{|i| resource_data << [i, resource_hash[i]] }
      end
      data
    end

    def has_distribution_plot?
      [:time, :memory, :frontend].include?(plot_kind)
    end

    def get_data_for_distribution_plot(what_to_plot)
      case what_to_plot
      when :request_time
        resources = Resource.time_resources
        kind = "t"
      when :frontend_time
        resources = Resource.frontend_resources - %w(frontend_time)
        kind = "f"
      when :allocated_objects
        resources = %w(allocated_objects)
        kind = "m"
      when :allocated_bytes
        resources = %w(allocated_bytes)
        kind = "m"
      end
      @the_quants = Quants.new(@db, resources, page, kind)
    end

    BUCKETS = [
      1,            #    1   ms               1 object            1   KB
      3,            #    3   ms               3 objects           3   KB
      10,           #   10   ms              10 objects          10   KB
      30,           #   30   ms              30 objects          30   KB
      100,          #  100   ms             100 objects         100   KB
      300,          #  300   ms             300 objects         300   KB
      1000,         #    1   second          1K objects       ~   1   MB
      3000,         #    3   seconds         2K objects       ~   2.9 MB
      10000,        #   10   seconds        10K objects       ~   9.7 MB
      30000,        #   30   seconds        30K objects       ~  29.3 MB
      100000,       #  100   seconds       100K objects       ~  97.6 MB
      300000,       #    5   minutes       300K objects       ~ 293   MB
      1000000,      # ~ 17   minutes         1M objects       ~ 976   MB
      3000000,      #   50   minutes         3M objects       ~   2.9 GB
      10000000,     #  ~ 2.6 hours          10M objects       ~   9.7 GB
      30000000,     #  ~ 8.3 hours          30M objects       ~  28.9 GB
      100000000,    #  ~ 1.2 days          100M objects       ~  96.3 GB
      300000000,    #    3.5 days          300M objects       ~ 289   GB
      1000000000,   #   11.6 days            1B objects       ~ 963   GB
      3000000000,   #   34.7 days            3B objects       ~   2.8 TB
      10000000000,  #  116   days           10B objects       ~   9.4 TB
      30000000000,  #  347   days           30B objects       ~  28.2 TB
      0
    ]

    EMPTY_BUCKETS = BUCKETS[0..-2].each_with_object({}) do |b, buckets|
      buckets[b] = 0
    end

    def bucket(v)
      i = 0
      while (b = BUCKETS[i]) < v && b != 0
        i += 1
      end
      b > 0 ? b : BUCKETS[i-1]
    end

    def compute_buckets(resource)
      quants = @the_quants.quants(resource)
      # Rails.logger.debug "#{resource}:quants:" + quants.inspect
      return {} if quants.blank?
      EMPTY_BUCKETS.clone.tap do |buckets|
        quants.each do |quant, count|
          buckets[bucket(quant)] += count
        end
      end
    end

    def histogram_data(resource)
      buckets = compute_buckets(resource)
      # Rails.logger.debug "#{resource}:buckets:" + buckets.inspect
      points = []
      buckets.keys.sort.each{|x| points << [x, buckets[x]] } unless buckets.blank?
      count = points.map(&:second).sum
      return {} if count == 0
      c90 = count * 0.90
      c95 = count * 0.95
      c99 = count * 0.99
      n = i = 0
      l = points.size
      while n < c90 && i < l
        n += points[i][1]
        i += 1
      end
      p90 = points[i-1][0]
      while n < c95 && i < l
        n += points[i][1]
        i += 1
      end
      p95 = points[i-1][0]
      while n < c99 && i < l
        n += points[i][1]
        i += 1
      end
      p99 = points[i-1][0]
      {buckets: buckets, percentiles: {p90: p90, p95: p95, p99: p99}}
    end

    def happy_count(section = :backend)
      totals.apdex(section)["happy"].to_i
    end

    def happy(section = :backend)
      happy_count(section) / totals.count(section).to_f
    end

    def satisfied_count(section = :backend)
      totals.apdex(section)["satisfied"].to_i
    end

    def satisfied(section = :backend)
      satisfied_count(section) / totals.count(section).to_f
    end

    def tolerating_count(section = :backend)
      totals.apdex(section)["tolerating"].to_i
    end

    def tolerating(section = :backend)
      tolerating_count(section) / totals.count(section).to_f
    end

    def frustrated_count(section = :backend)
      totals.apdex(section)["frustrated"].to_i
    end

    def frustrated(section = :backend)
      frustrated_count(section) / totals.count(section).to_f
    end

    def apdex(section = :backend)
      satisfied(section) + tolerating(section) / 2.0
    end

    def error_count
      response_codes[500] || 0
    end

    def severities
      totals.severities
    end

    def logged_error_count(level)
      severities[level] || 0
    end

    def logged_error_count_above(level)
      (level..5).to_a.map{|l| logged_error_count(l) }.sum
    end

    def exceptions
      totals.exceptions
    end

    def exception_count
      totals.exception_count
    end

    def soft_exceptions
      totals.soft_exceptions
    end

    def soft_exception_count
      totals.soft_exception_count
    end

    def js_exception_count
      totals.js_exception_count
    end

    def response_codes
      totals.response_codes
    end

    def response_codes_above(response_code)
      response_codes.select{|k,v| k.to_i >= response_code}.values.sum
    end

    def empty_response_code_summy
      Hash.new(0).merge!("1xx" => 0, "2xx" => 0, "3xx" => 0, "4xx" => 0, "5xx" => 0)
    end

    def response_code_summary
      @response_code_summary ||=
        response_codes.each_with_object(empty_response_code_summy) do |(rc,c),s|
          rc_s = rc > 999 ? "?xx" : sprintf("%03d", rc).first + "xx"
          s[rc_s] += c
        end
    end
  end
end

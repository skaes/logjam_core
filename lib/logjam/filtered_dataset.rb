module Logjam

  class FilteredDataset
    HEAP_SLOT_SIZE = 40

    attr_accessor :interval, :page, :response_code,
    :plot_kind, :heap_growth_only, :resource, :grouping, :grouping_function,
    :start_minute, :end_minute, :date

    DEFAULTS = {:plot_kind => :time, :interval => '5',
      :grouping => 'page', :resource => 'total_time', :grouping_function => 'sum',
      :start_minute => '0', :end_minute => '1440'}

    def self.is_default?(attribute, value)
      DEFAULTS.keys.include?(attribute.to_sym) && DEFAULTS[attribute.to_sym].to_s == value
    end

    def self.clean_url_params(params)
      params.reject{|k,v| v.blank? || is_default?(k, v)}
    end

    def initialize(options = {})
      @date = options[:date]
      @app = options[:app]
      @env = options[:env]
      @db = Logjam.db(@date, @app, @env)
      @interval = (options[:interval] || DEFAULTS[:interval]).to_i
      @page = options[:page].to_s
      @response_code = options[:response_code] if options[:response_code].present?
      @heap_growth_only = options[:heap_growth_only].present?
      @plot_kind = options[:plot_kind] || DEFAULTS[:plot_kind]
      @resource = options[:resource] || DEFAULTS[:resource]
      @grouping = options[:grouping]
      @grouping_function = options[:grouping_function] || DEFAULTS[:grouping_function]
      @start_minute = (options[:start_minute] || DEFAULTS[:start_minute]).to_i
      @end_minute = (options[:end_minute] || DEFAULTS[:end_minute]).to_i
    end

    def page_description
      page == "::" ? "all pages" : page
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
      (Resource.resource_type(resource) == :time) && grouping? && [:sum, :avg, :stddev, :count].include?(grouping_function.to_sym)
    end

    def intervals_per_day
      24 * 60 / interval
    end

    def intervals_per_hour
      60 / interval
    end

    def live_stream?
      (@date == Date.today || Rails.env == "development") && (page.blank? || page == "all_pages" || page =~ /^::/)
    end

    def empty?
      count_requests == 0
    end

    def count_requests
      totals.count.to_i
    end

    def count
      @count ||= Totals.new(@db, [], "all_pages").count.to_i
    end

    def sum(time_attr = 'total_time')
      totals.sum(time_attr)
    end

    def single_page?
      totals.the_pages.size == 1
    end

    def do_the_query
      @query_result ||=
        if grouping == "request"
          query_opts = {:heap_growth_only => heap_growth_only, :start_minute => @start_minute, :end_minute => @end_minute}
          Requests.new(@db, resource, page, query_opts).all
        else
          if grouping_function.to_sym == :count
            sort_by = "count"
          else
            sort_by = "#{resource}_#{grouping_function}"
          end
          totals.pages(:order => sort_by, :limit => 20)
        end
    end

    def totals
      @totals ||=
        case Resource.resource_type(resource)
        when :time   then Totals.new(@db, Resource.time_resources+%w(apdex response), page)
        when :call   then Totals.new(@db, Resource.call_resources, page)
        when :memory then Totals.new(@db, Resource.memory_resources, page)
        end
    end

    def summary
      @summary ||=
        begin
          resources = Resource.time_resources + Resource.call_resources +
            Resource.memory_resources + Resource.heap_resources - %w(heap_growth) + %w(apdex response)
          Totals.new(@db, resources, page)
        end
    end

    def measures_bytes?(attr)
      [:allocated_memory, :allocated_bytes].include? attr.to_sym
    end

    def statistics
      @statistics ||= totals
    end

    YLABELS = {:time => 'Response time (ms)', :call => '# of calls', :memory => 'Allocations (bytes)'}

    def ylabel
      YLABELS[plot_kind] || ""
    end

    def resources_excluded_from_plot
      ['total_time', 'allocated_memory', 'requests']
    end

    def plotted_resources
      Resource.resources_for_type(plot_kind) - resources_excluded_from_plot
    end

    def plot_data
      @plot_data ||=
        begin
          resources = plotted_resources
          mins = Minutes.new(@db, resources, page, interval)
          minutes = mins.minutes
          counts = mins.counts
          max_total = 0
          plot_resources = resources.clone
          plot_resources += ["gc_time"] if plot_resources.delete("gc_time")
          zero = Hash.new(0.0)
          results = plot_resources.inject({}){|h,r| h[r] = {}; h}
          totals = []
          nonzero = 0
          intervals_per_day.times do |i|
            row = minutes[i] || zero
            total = 0
            plot_resources.each do |r|
              v = row[r]
              total += v unless r == "gc_time"
              results[r][i] = v
            end
            totals << total if total > 0
            max_total = total if max_total < total
            nonzero += 1 if total > 0
          end
          plot_data = data_for_proto_vis(results, plot_resources).reverse
          gc_time = plot_data.shift if resources.include?("gc_time")
          request_counts = []
          intervals_per_day.times{|i| request_counts << (counts[i] || 0) / 60.0}
          y_zoom = totals.sort[(totals.size*0.9).to_i].to_f
          [plot_data, max_total, request_counts, gc_time, y_zoom]
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

    def get_data_for_distribution_plot(what_to_plot)
      case what_to_plot
      when :request_time
        resources = Resource.time_resources
        kind = "t"
      when :allocated_objects
        resources = %w(allocated_objects)
        kind = "m"
      when :allocated_bytes
        resources = %w(allocated_bytes)
        kind = "m"
      end
      @the_quants = Quants.new(@db, resources, page, kind)
    end

    def histogram_data(resource)
      quantized = @the_quants.quants(resource)
      points = []
      quantized.keys.sort.each{|x| points << [x, quantized[x]] } unless quantized.blank?
      points
    end

    def satisfaction
      @satisfaction ||= Totals.new(@db, %w(apdex), page)
    end

    def happy
      satisfaction.apdex["happy"].to_f / satisfaction.count.to_f
    end

    def satisfied
      satisfaction.apdex["satisfied"].to_f / satisfaction.count.to_f
    end

    def tolerating
      satisfaction.apdex["tolerating"].to_f / satisfaction.count.to_f
    end

    def frustrated
      satisfaction.apdex["frustrated"].to_f / satisfaction.count.to_f
    end

    def apdex
      satisfied + tolerating / 2.0
    end

    def error_count
      response_codes[500] || 0
    end

    def logged_error_count(level)
      @logged_error_count ||= Requests.new(@db, "minute", @page, :severity => level).count
    end

    def response_codes
      @response_codes ||= Totals.new(@db, %w(response), page).response_codes
    end
  end
end

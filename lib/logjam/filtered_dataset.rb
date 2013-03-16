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
      default_app = params.delete(:default_app) || Logjam.default_app
      params = params.reject{|k,v| v.blank? || is_default?(k, v)}
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
      @collected_resources = options[:collected_resources]
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
      @count ||= totals.request_count
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

    def resource_fields
      case Resource.resource_type(resource)
      when :time   then Resource.time_resources
      when :call   then Resource.call_resources
      when :memory then Resource.memory_resources
      when :heap   then Resource.heap_resources
      end & @collected_resources
    end

    def totals
      @totals ||= Totals.new(@db, %w(apdex response severity exceptions) + resource_fields, page)
    end

    def summary
      @summary ||=
        begin
          all_resources = Resource.time_resources + Resource.call_resources + Resource.memory_resources + Resource.heap_resources
          resources = (all_resources & @collected_resources) - %w(heap_growth) + %w(apdex response)
          Totals.new(@db, resources, page, totals.page_names)
        end
    end

    def measures_bytes?(attr)
      [:allocated_memory, :allocated_bytes].include? attr.to_sym
    end

    YLABELS = { :time => 'Response time (ms)', :call => '# of calls',
                :memory => 'Allocations (bytes)', :heap => 'Heap size (slots)'}

    def ylabel
      YLABELS[plot_kind] || ""
    end

    def resources_excluded_from_plot
      %w(total_time allocated_memory requests heap_growth)
    end

    def plotted_resources
      (Resource.resources_for_type(plot_kind) & @collected_resources) - resources_excluded_from_plot
    end

    def plot_data
      @plot_data ||=
        begin
          resources = plotted_resources
          mins = Minutes.new(@db, resources, page, totals.page_names, interval)
          minutes = mins.minutes
          counts = mins.counts
          max_total = 0
          plot_resources = resources.clone
          plot_resources += ["gc_time"] if plot_resources.delete("gc_time")
          plot_resources.unshift("free_slots") if plot_resources.delete("heap_size")
          zero = Hash.new(0.0)
          results = plot_resources.inject({}){|h,r| h[r] = {}; h}
          totals = []
          nonzero = 0
          intervals_per_day.times do |i|
            row = minutes[i] || zero
            total = 0
            plot_resources.each do |r|
              v = r == "free_slots" ? row["heap_size"] - row["live_data_set_size"] : row[r]
              total += v unless r == "gc_time"
              results[r][i] = v
            end
            totals << total if total > 0
            max_total = total if max_total < total
            nonzero += 1 if total > 0
          end
          puts results.inspect
          plot_data = data_for_proto_vis(results, plot_resources).reverse
          gc_time = plot_data.shift if resources.include?("gc_time")
          request_counts = []
          intervals_per_day.times{|i| request_counts << (counts[i] || 0) / 60.0}
          y_zoom = totals.sort[(totals.size*0.9).to_i].to_f
          [plot_resources-["gc_time"], plot_data, max_total, request_counts, gc_time, y_zoom]
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

    def happy_count
      totals.apdex["happy"].to_i
    end

    def happy
      happy_count / totals.count.to_f
    end

    def satisfied_count
      totals.apdex["satisfied"].to_i
    end

    def satisfied
      satisfied_count / totals.count.to_f
    end

    def tolerating_count
      totals.apdex["tolerating"].to_i
    end

    def tolerating
      tolerating_count / totals.count.to_f
    end

    def frustrated_count
      totals.apdex["frustrated"].to_i
    end

    def frustrated
      frustrated_count / totals.count.to_f
    end

    def apdex
      satisfied + tolerating / 2.0
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

    def exceptions
      totals
    end

    def exception_count
      totals.exception_count
    end

    def response_codes
      totals.response_codes
    end
  end
end

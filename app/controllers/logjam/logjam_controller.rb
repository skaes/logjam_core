module Logjam

  class LogjamController < ApplicationController
    before_filter :redirect_to_clean_url, :except => [:live_stream, :auto_complete_for_controller_action_page]
    before_filter :print_params if RAILS_ENV=="development"

    def auto_complete_for_controller_action_page
      prepare_params
      show_modules = [":", "::"].include?(@page)
      re = show_modules ? /^::/ : /#{@page}/i
      pages = Totals.new(@db).page_names.select {|name| name =~ re}
      pages.collect!{|p| p.gsub(/^::/,'')} unless show_modules
      @completions = pages.sort[0..34]
      render :inline => "<%= content_tag(:ul, @completions.map{ |page| content_tag(:li, page) }.join) %>"
    end

    def index
      @dataset = dataset_from_params
      @protovis_data, @protovis_max, @request_counts, @gc_time, @protovis_avg = @dataset.plot_data
      @resources = @dataset.plotted_resources-["gc_time"]
    end

    def show
      get_date
      @request = Requests.new(@db).find(params[:id])
    end

    def errors
      get_date
      @page = params[:page]
      if params[:error_type] == "internal"
        q = Requests.new(@db, "minute", @page, :response_code => 500, :limit => 500)
      else
        q = Requests.new(@db, "minute", @page, :severity => 2, :limit => 500)
      end
      @error_count = q.count
      @requests = q.all
    end

    def enlarged_plot
      @dataset = dataset_from_params
      @protovis_data, @protovis_max, @request_counts, @gc_time, @protovis_avg = @dataset.plot_data
      @resources = @dataset.plotted_resources-["gc_time"]
    end

    def request_time_distribution
      @resources = Logjam::Resource.time_resources
      @dataset = dataset_from_params
      @dataset.get_data_for_distribution_plot(:request_time)
      @xmin = 100
      @xlabel = "Request time"
      render 'quants_plot'
    end

    def allocated_objects_distribution
      @resources = Logjam::Resource.memory_resources
      @dataset = dataset_from_params
      @dataset.get_data_for_distribution_plot(:allocated_objects)
      @xmin = 10000
      @xlabel = "Allocated objects"
      render 'quants_plot'
    end

    def allocated_size_distribution
      @resources = Logjam::Resource.memory_resources
      @dataset = dataset_from_params
      @dataset.get_data_for_distribution_plot(:allocated_bytes)
      @xmin = 100000
      @xlabel = "Allocated memory (bytes)"
      render 'quants_plot'
    end

    def live_stream
      get_app_env
      @resources = Logjam::Resource.time_resources-%w(total_time gc_time)
      @socket_url = "ws://#{request.host}:8080/"
      @key = params[:page].to_s
      @key = "all_pages" if @key.blank? || @key == "::"
      @key = @key.sub(/^::/,'').downcase
    end

    private

    def default_date
      (Logjam.database_days(params[:app], params[:env]).first || Date.today).to_date
    end

    def get_app_env
      @app = params[:app] || Logjam.database_apps.first
      @env = params[:env] || Logjam.database_envs(@app).first
    end

    def get_date
      @date = "#{params['year']}-#{params['month']}-#{params['day']}".to_date unless params[:year].blank?
      @date ||= default_date
      get_app_env
      @db = Logjam.db(@date, @app, @env)
    end

    def prepare_params
      get_date
      params[:start_minute] ||= FilteredDataset::DEFAULTS[:start_minute]
      params[:end_minute] ||= FilteredDataset::DEFAULTS[:end_minute]
      params[:resource] ||= FilteredDataset::DEFAULTS[:resource]
      params[:grouping] ||= FilteredDataset::DEFAULTS[:grouping]
      params[:grouping_function] ||= FilteredDataset::DEFAULTS[:grouping_function]
      @plot_kind = Resource.resource_type(params[:resource])
      @attributes = Resource.resources_for_type(@plot_kind)
      @page = params[:page]
    end

    def dataset_from_params
      prepare_params
      params[:page] = @page
      params[:interval] ||= FilteredDataset::DEFAULTS[:interval]

      FilteredDataset.new(
        :date => @date,
        :app => @app,
        :env => @env,
        :interval => params[:interval].to_i,
        :page => @page,
        :heap_growth_only => params[:heap_growth_only],
        :plot_kind => @plot_kind,
        :resource => params[:resource] || :total_time,
        :grouping => params[:grouping],
        :grouping_function => (params[:grouping_function] || :avg).to_sym,
        :start_minute => params[:start_minute].to_i,
        :end_minute => params[:end_minute].to_i)
    end

    def redirect_to_clean_url
      params[:starts_at] ||= default_date.to_s(:db) unless (params[:year] && params[:month] && params[:day])
      if params[:starts_at] =~ /^(\d\d\d\d)-(\d\d)-(\d\d)$/
        redirect_to(FilteredDataset.clean_url_params(
          :controller => params[:controller], :action => params[:action],
          :year => $1, :month => $2, :day => $3, :interval => params[:interval],
          :start_minute => params[:start_minute], :end_minute => params[:end_minute],
          :app => params[:app], :env => params[:env],
          :page => params[:page], :response => params[:response],
          :heap_growth_only => params[:heap_growth_only], :resource => params[:resource],
          :grouping => params[:grouping], :grouping_function => params[:grouping_function]))
      end
    end

    def print_params
      p params
    end

  end
end

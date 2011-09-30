module Logjam

  class LogjamController < ApplicationController
    before_filter :redirect_to_clean_url, :except => [:live_stream, :auto_complete_for_controller_action_page]
    before_filter :verify_app_env
    before_filter :print_params if ::Rails.env=="development"

    def auto_complete_for_controller_action_page
      params[:page] = params.delete(:term)
      prepare_params
      show_modules = [":", "::"].include?(@page)
      re = show_modules ? /^::/ : /#{@page}/i
      pages = Totals.new(@db).page_names.select {|name| name =~ re}
      pages.collect!{|p| p.gsub(/^::/,'')} unless show_modules
      completions = pages.sort[0..34]
      render :json => completions
    end

    def index
      @dataset = dataset_from_params
      @protovis_data, @protovis_max, @request_counts, @gc_time, @protovis_zoom = @dataset.plot_data
      @resources = @dataset.plotted_resources-["gc_time"]
    end

    def show
      get_date
      @request = Requests.new(@db).find(params[:id])
    end

    def errors
      get_date
      @page_size = 25
      @page = params[:page]
      if params[:error_type] == "internal"
        @title = "Internal Server Errors"
        q = Requests.new(@db, "minute", @page, :response_code => 500, :limit => @page_size, :skip => params[:offset].to_i)
      elsif params[:error_type] == "exceptions"
        @title = "Requests with '#{params[:exception]}'"
        q = Requests.new(@db, "minute", @page, :exceptions => params[:exception], :limit => @page_size, :skip => params[:offset].to_i)
      else
        severity = case params[:error_type]
                   when "logged_warning"; then 2
                   when "logged_error"; then 3
                   when "logged_fatal"; then 4
                   else 5
                   end
        @title = severity == 2 ? "Logged Warnings" : "Logged Errors"
        q = Requests.new(@db, "minute", @page, :severity => severity, :limit => @page_size, :skip => params[:offset].to_i)
      end
      @error_count = q.count
      @requests = q.all
      offset = params[:offset].to_i
      @page_count = @error_count/@page_size + 1
      @current_page = offset/@page_size + 1
      @last_page = @page_count
      @last_page_offset = @error_count/@page_size*@page_size
      @next_page_offset = offset + @page_size
      @previous_page_offset = [offset - @page_size, 0].max
    end

    def response_codes
      get_date
      @page_size = 25
      @page = params[:page]
      if (@response_code = params[:above].to_i) >= 400
        @title = "Requests with response code above #{@response_code}"
      else
        @response_code = params[:response_code].to_i
        @title = "Requests with response code #{@response_code}"
      end
      q = Requests.new(@db, "minute", @page, :response_code => @response_code, :limit => @page_size, :skip => params[:offset].to_i, :above => params[:above].present?)
      @error_count = q.count
      @requests = q.all
      offset = params[:offset].to_i
      @page_count = @error_count/@page_size + 1
      @current_page = offset/@page_size + 1
      @last_page = @page_count
      @last_page_offset = @error_count/@page_size*@page_size
      @next_page_offset = offset + @page_size
      @previous_page_offset = [offset - @page_size, 0].max
      render "errors"
    end

    def exceptions
      get_date
      @page = params[:page]
      @title = "Logged Exceptions"
      @totals = Totals.new(@db, ["exceptions"], @page)
    end

    def enlarged_plot
      @dataset = dataset_from_params
      @protovis_data, @protovis_max, @request_counts, @gc_time, @protovis_zoom = @dataset.plot_data
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

    def logjam_databases
      @logjam_databases ||= Logjam.databases
    end

    def default_date
      (Logjam.database_days(params[:app], params[:env], logjam_databases).first || Date.today).to_date
    end

    def get_app_env
      @default_app ||= Logjam.default_app(logjam_databases)
      @app ||= (params[:app] ||= @default_app)
      @default_env ||= Logjam.default_env(@app, logjam_databases)
      @env ||= (params[:env] ||= @default_env)
    end

    def get_date
      get_app_env
      @date = "#{params['year']}-#{params['month']}-#{params['day']}".to_date unless params[:year].blank?
      @date ||= default_date
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
      get_app_env
      py, pm, pd = params.values_at(:year, :month, :day).map(&:to_i)
      dd = default_date
      params[:starts_at] = dd.to_s(:db) if params[:auto_refresh] == "1" && (dd.year != py || dd.month != pm || dd.day != pd)
      params[:starts_at] ||= dd.to_s(:db) unless (params[:year] && params[:month] && params[:day])
      if params[:starts_at] =~ /^(\d\d\d\d)-(\d\d)-(\d\d)$/
        redirect_to(FilteredDataset.clean_url_params(
          :auto_refresh => params[:auto_refresh] == "1" ? "1" : nil,
          :default_app => @default_app, :default_env => @default_env,
          :controller => params[:controller], :action => params[:action],
          :year => $1, :month => $2, :day => $3, :interval => params[:interval],
          :start_minute => params[:start_minute], :end_minute => params[:end_minute],
          :app => params[:app], :env => params[:env],
          :page => params[:page], :response => params[:response],
          :heap_growth_only => params[:heap_growth_only], :resource => params[:resource],
          :offset => params[:offset], :error_type => params[:error_type],
          :grouping => params[:grouping], :grouping_function => params[:grouping_function]))
      end
    end

    def print_params
      p params
    end

    def verify_app_env
      get_app_env
      unless Logjam.database_apps(logjam_databases).include?(@app)
        render :text => "Application '#{@app}' doesn't exist."
        return
      end
      unless Logjam.database_envs(@app, logjam_databases).include?(@env)
        render :text => "Environment '#{@env}' doesn't exist for Application '#{@app}'."
        return
      end
    end
  end
end

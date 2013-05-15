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
      @resources, @js_data, @js_events, @js_max, @request_counts, @gc_time, @js_zoom = @dataset.plot_data
    end

    def show
      prepare_params
      unless @request = Requests.new(@db).find(params[:id])
        render :file => "#{Rails.root}/public/404.html", :status => :not_found
      end
    end

    def errors
      prepare_params
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
      prepare_params
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
      prepare_params
      @page = params[:page]
      @title = "Logged Exceptions"
      @totals = Totals.new(@db, ["exceptions"], @page)
      @minutes = Minutes.new(@db, ["exceptions"], @page, @totals.page_names, 2)
    end

    def callers
      prepare_params
      @page = params[:page]
      @title = "Callers of action"
      @totals = Totals.new(@db, ["callers"], @page)
    end

    def enlarged_plot
      @dataset = dataset_from_params
      @resources, @js_data, @js_events, @js_max, @request_counts, @gc_time, @js_zoom = @dataset.plot_data
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
      ws_port = RUBY_PLATFORM =~ /darwin/ ? 9608 : 8080
      @socket_url = "ws://#{request.host}:#{ws_port}/"
      @key = params[:page].to_s
      @key = "all_pages" if @key.blank? || @key == "::"
      @key = @key.sub(/^::/,'').downcase
    end

    private

    def database_info
      @database_info ||= Logjam::DatabaseInfo.new
    end

    def default_date
      (database_info.days(params[:app], params[:env]).first || Date.today).to_date
    end

    def get_app_env
      @default_app ||= database_info.default_app
      @app ||= (params[:app] ||= (session[:last_app] || @default_app))
      session[:last_app] = @app
      @apps ||= database_info.apps
      @default_env ||= database_info.default_env(@app)
      @env ||= (params[:env] ||= @default_env)
      @envs ||= database_info.envs(@app)
      @only_one_app = database_info.only_one_app?
      @only_one_env = database_info.only_one_env?(@app)
    end

    def get_date
      get_app_env
      @date = "#{params['year']}-#{params['month']}-#{params['day']}".to_date unless params[:year].blank?
      @date ||= default_date
      @days = database_info.days(@app, @env)
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
      @collected_resources = Totals.new(@db).collected_resources
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
        :plot_kind => @plot_kind,
        :resource => params[:resource] || :total_time,
        :collected_resources => @collected_resources,
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
        new_params = FilteredDataset.clean_url_params(
          :auto_refresh => params[:auto_refresh] == "1" ? "1" : nil,
          :default_app => @default_app, :default_env => @default_env,
          :controller => params[:controller], :action => params[:action],
          :year => $1, :month => $2, :day => $3, :interval => params[:interval],
          :start_minute => params[:start_minute], :end_minute => params[:end_minute],
          :app => params[:app], :env => params[:env],
          :page => params[:page], :response => params[:response],
          :resource => params[:resource],
          :offset => params[:offset], :error_type => params[:error_type],
          :grouping => params[:grouping], :grouping_function => params[:grouping_function])
        redirect_to new_params
      end
    end

    def print_params
      p params
    end

    def verify_app_env
      get_app_env
      unless @apps.include?(@app)
        render :text => "Application '#{@app}' doesn't exist."
        return
      end
      unless @envs.include?(@env)
        render :text => "Environment '#{@env}' doesn't exist for Application '#{@app}'."
        return
      end
    end
  end
end

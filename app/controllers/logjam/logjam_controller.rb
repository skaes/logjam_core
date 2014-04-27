# -*- coding: utf-8 -*-
require 'csv'
module Logjam

  class LogjamController < ApplicationController
    before_filter :redirect_to_clean_url, :except => [:live_stream, :auto_complete_for_controller_action_page]
    before_filter :verify_app_env, :except => [:call_relationships, :call_graph]
    before_filter :print_params if Rails.env=="development"
    # after_filter :allow_cross_domain_ajax

    def auto_complete_for_controller_action_page
      query = params[:page] = params.delete(:query)
      prepare_params
      show_modules = [":", "::"].include?(@page)
      re = show_modules ? /^::/ : /#{@page}/i
      pages = Totals.new(@db).page_names.select {|name| name =~ re && name != 'all_pages'}
      pages.collect!{|p| p.gsub(/^::/,'')}
      completions = pages.sort  # [0..34]
      render :json => {query: query, suggestions: completions}
    end

    def index
      respond_to do |format|
        format.html do
          redirect_on_empty_dataset and return
          @resources, @js_data, @js_events, @js_max, @request_counts, @gc_time, @js_zoom = @dataset.plot_data
        end
        format.json do
          prepare_params
          pages, events = fetch_json_data_for_index(@db, @page)
          render :json => Oj.dump({:pages => pages, :events => events}, :mode => :compat)
        end
      end
    end

    def fetch_json_data_for_index(db, page, options = params)
      resources = Resource.all_resources + %w(apdex response severity exceptions js_exceptions)
      stream = Logjam.streams["#{@app}-#{@env}"]
      filter = stream.frontend_page if options[:frontend_only] == "1"
      pages = Totals.new(db, resources, page).pages(:order => :apdex, :limit => 100_000, :filter => filter)
      if pages.size > 0 && options[:summary] == "1"
        summary = pages.shift
        summary.page = "__summary__"
        while p = pages.shift
          summary.add(p)
        end
        pages = [summary]
      end
      events = Events.new(db).events.map{|e| {:label => e['label'], :time => e['started_at']}}
      [pages, events]
    end
    private :fetch_json_data_for_index

    def history
      respond_to do |format|
        format.html do
          redirect_on_empty_dataset and return
        end
        format.json do
          prepare_params
          page = @page
          page_names = Totals.new(@db).page_names
          page = /^#{page}$/ if @page =~ /\A::/ && page_names.include?(page)
          page = /^::#{page}$/ if @page !~ /\A::/ && page_names.include?("::#{page}")
          page = 'all_pages' if @page == '' || @page == '::'
          resources = %w(apdex severity exceptions total_time) + (Resource.all_resources - %w(total_time))
          databases = Logjam.grep(Logjam.databases, :app => @app, :env => @env)
          data = []
          today = Date.today
          databases.each do |db_name|
            date_str = Logjam.iso_date_string(db_name)
            date = Date.parse(date_str)
            next if date == today
            db = Logjam.connection_for(db_name).db(db_name)
            if summary = Totals.new(db, resources, page).pages(:limit => 1).try(:first)
              hash = {
                :date => date_str,
                :request_count => summary.count,
                :errors => summary.error_count,
                :warnings => summary.warning_count,
                :exceptions => summary.exception_count,
                :apdex_score => summary.apdex_score
              }
              Resource.all_resources.each do |r|
                if (v = summary.avg(r)) != 0
                  hash[r.to_sym] = v
                end
              end
            else
              hash = { :date => date_str }
            end
            data << hash
          end
          data = data.sort_by{|d| d[:date]}  # .drop_while{|d| !d.has_key?(:request_count)}
          data << { :date => (Date.parse(data.last[:date])+1).iso8601 } unless data.empty?
          collected_resources = data.inject(Set.new){|s,d| s.union(d.keys)}
          resources.reject!{|r| !collected_resources.include?(r.to_sym)}
          # logger.debug @data.inspect
          json_hash = {
            :resources => {
              :time => Resource.time_resources.reverse & resources,
              :calls => Resource.call_resources.reverse & resources,
              :memory => Resource.memory_resources & resources,
              :heap => Resource.heap_resources & resources
            },
            :data => data
          }
          render :json => Oj.dump(json_hash, :mode => :compat)
        end
      end
    end

    def show
      prepare_params
      logjam_request_id = [@app, @env, params[:id]].join('-')
      @js_exceptions = Logjam::JsExceptions.new(@db).find_by_request(logjam_request_id)
      @request = Requests.new(@db).find(params[:id])
      respond_to do |format|
        format.html do
          unless @request || @js_exceptions.present?
            render :file => "#{Rails.root}/public/404.html", :status => :not_found
          end
        end
        format.json do
          render :json => Oj.dump(@request||["NOT FOUND"], :mode => :compat)
        end
      end
    end

    def errors
      redirect_on_empty_dataset and return
      @page_size = 25
      case params[:error_type]
      when "internal"
        @title = "Internal Server Errors"
        q = Requests.new(@db, "minute", @page, :response_code => 500, :limit => @page_size, :skip => params[:offset].to_i)
        @error_count = @dataset.response_codes[500]
      when "exceptions"
        @title = "Requests with exception «#{params[:exception]}»"
        q = Requests.new(@db, "minute", @page, :exceptions => params[:exception], :limit => @page_size, :skip => params[:offset].to_i)
        @error_count = @dataset.exceptions[params[:exception]]
      else
        severity, @title, @error_count = case params[:error_type]
                   when "logged_warning"; then [2, "Logged Warnings", @dataset.logged_error_count(2)]
                   when "logged_error"; then [3, "Logged Errors", @dataset.logged_error_count_above(3)]
                   when "logged_fatal"; then [4, "Logged Fatal Errors", @dataset.logged_error_count_above(4)]
                   else [3, "Logged Errors", @dataset.logged_error_count_above(3)]
                   end
        q = Requests.new(@db, "minute", @page, :severity => severity, :limit => @page_size, :skip => params[:offset].to_i)
      end
      @requests = q.all
      offset = params[:offset].to_i
      @page_count = @error_count/@page_size + 1
      @current_page = offset/@page_size + 1
      @last_page = @page_count
      @last_page_offset = @error_count/@page_size*@page_size
      @next_page_offset = offset + @page_size
      @previous_page_offset = [offset - @page_size, 0].max
    end

    def js_exceptions
      redirect_on_empty_dataset and return
      @page_size = 25
      offset = params[:offset].to_i

      exceptions = JsExceptions.new(@db)
      description = JsExceptions.description_from_key(params[:js_exception])

      @title = "Javascript Exceptions"
      options = { selector: { description: description } }
      @error_count = exceptions.count(options)
      options[:skip] = offset
      options[:limit] = @page_size

      @exceptions = exceptions.find(options)
      @current_page = offset/@page_size + 1
      @page_count = @error_count/@page_size + 1
      @last_page = @page_count
      @last_page_offset = @error_count/@page_size*@page_size
      @next_page_offset = offset + @page_size
      @previous_page_offset = [offset - @page_size, 0].max
    end

    def response_codes
      redirect_on_empty_dataset and return
      @page_size = 25
      @page = params[:page]
      if (@response_code = params[:above].to_i) >= 400
        @title = "Requests with response code above #{@response_code}"
        @error_count = @dataset.response_codes_above(@response_code)
      else
        @response_code = params[:response_code].to_i
        @title = "Requests with response code #{@response_code}"
        @error_count = @dataset.response_codes[@response_code] || 0
      end
      q = Requests.new(@db, "minute", @page, :response_code => @response_code, :limit => @page_size, :skip => params[:offset].to_i, :above => params[:above].present?)
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

    def totals_overview
      redirect_on_empty_dataset(true) and return
      @dataset.limit = 100_000
    end

    def request_overview
      redirect_on_empty_dataset and return
      @page_size = 25
      offset = params[:offset].to_i
      @dataset.limit = @page_size
      @dataset.offset = offset
      @requests = @dataset.do_the_query
      @request_count = @dataset.count_requests
      @page_count = @request_count/@page_size + 1
      @current_page = offset/@page_size + 1
      @last_page = @page_count
      @last_page_offset = @request_count/@page_size*@page_size
      @next_page_offset = offset + @page_size
      @previous_page_offset = [offset - @page_size, 0].max
      @skip_last = true
    end

    def error_overview
      redirect_on_empty_dataset and return
      @title = "Problem Overview"
      @resources = %w(exceptions js_exceptions severity response)
      @totals = Totals.new(@db, @resources, @page.blank? ? 'all_pages' : @page)
      @minutes = Minutes.new(@db, @resources, @page, @totals.page_names, 2)
    end

    def response_code_overview
      redirect_on_empty_dataset and return
      @title = "Response Code Overview"
      @resources = %w(response)
      @totals = Totals.new(@db, @resources, @page.blank? ? 'all_pages' : @page)
      @minutes = Minutes.new(@db, @resources, @page, @totals.page_names, 2)
    end

    def apdex_overview
      redirect_on_empty_dataset and return
      @title = "Apdex Overview"
      @resources = %w(apdex)
      @totals = Totals.new(@db, @resources, @page.blank? ? 'all_pages' : @page)
      @minutes = Minutes.new(@db, @resources, @page, @totals.page_names, 2)
    end

    def exceptions
      redirect_on_empty_dataset and return
      @title = "Logged Exceptions"
      @totals = Totals.new(@db, ["exceptions"], @page.blank? ? 'all_pages' : @page)
      @minutes = Minutes.new(@db, ["exceptions"], @page, @totals.page_names, 2)
    end

    def callers
      redirect_on_empty_dataset and return
      params[:sort] ||= 'count'
      params[:group] ||= 'module'
      @callers = Totals.new(@db, ["callers"], @page).callers
      if transform = get_transform(params[:group])
        @callers = @callers.each_with_object(Hash.new(0)){|(k,v),h| h[transform.call(k)] += v}
      end
      respond_to do |format|
        format.html do
          @title = "Callers"
          @callers =
            case params[:sort]
            when 'name'
              @callers.sort_by{|k,v| k}
            else
              @callers.sort_by{|k,v| -v}
            end
          @call_count = @callers.blank? ? 0 : @callers.map(&:second).sum
          totals = Totals.new(@db, ["callers"], @page.blank? ? 'all_pages' : @page)
          @request_count = totals.count
          @caller_minutes = Minutes.new(@db, ["callers"], @page, totals.page_names, 2).callers
          # puts @caller_minutes.inspect
          if transform
            minutes = Hash.new{|h,k| h[k] = Hash.new(0)}
            @caller_minutes = @caller_minutes.each_with_object(minutes) do |(k,h),calls|
              callee = transform.call(k)
              counts = calls[callee]
              h.each {|m,c| counts[m] += c}
            end
            # puts @caller_minutes.inspect
          end
        end
        format.json do
          page = @page == 'all_pages' ? '::' : @page
          page.sub!(/\A::/,'')
          app = page == '' ? @app : "#{@app}::"
          target = "#{app}#{page}"
          array = @callers.map{|k,v| {source: k.sub('-','::'), target: target, count: v}}
          render :json => Oj.dump(array, :mode => :compat)
        end
      end
    end

    def get_transform(group)
      case group
      when 'module'
        ->(k) do
          p = k.gsub('∙','.').split('-')
          m = p[1].split(/(::)|#/)[0]
          # TODO: dirty hack
          m = p[0].capitalize if m =~ /Controller\z/
          "#{p[0]}-#{m}"
        end
      when 'application'
        ->(k){ k.gsub('∙','.').split('-')[0] }
      else
        ->(k){ k.gsub('∙','.') }
      end
    end
    private :get_transform

    def get_relationship_data(group=nil, filter=nil, sort=nil)
      filter_regexp = /#{filter}/i unless filter.blank?
      transform = get_transform(group)
      data = Hash.new(0)
      databases = Logjam.grep(Logjam.databases, :env => @env, :date => @date)
      databases.each do |db_name|
        stream = Logjam.stream_for(db_name)
        db = Logjam.connection_for(db_name).db(db_name)
        relationships = Totals.new(db).call_relationships(stream.app)
        relationships.each do |callee, callers|
          callee = transform.call(callee)
          callers.each do |caller, count|
            caller = transform.call(caller)
            next if filter_regexp && "#{caller},#{callee}" !~ filter_regexp
            data[[caller, callee]] += count.to_i
          end
        end
      end
      data = data.map{|p,c| {source: p[0], target: p[1], count: c}}
      case sort
      when 'caller' then data.sort_by!{|p| [p[:source],p[:target]]}
      when 'callee' then data.sort_by!{|p| [p[:target],p[:source]]}
      when 'count'  then data.sort_by!{|p| -p[:count]}
      end
      data
    end
    private :get_relationship_data

    def call_relationships
      prepare_params
      params[:group] ||= 'module'
      params[:sort] ||= 'caller'
      # only filter data when explicitly requested
      filter = params[:filter_data].to_s == '1' ? params[:filter].to_s : ''
      data = get_relationship_data(params[:group], filter, params[:sort])

      respond_to do |format|
        format.html do
          @title = "Call relationships across all aplications"
          @data = data
        end
        format.json do
          render :json => Oj.dump(data, :mode => :compat)
        end
        format.csv do
          str = CSV.generate(:col_sep => ';') do |csv|
            csv << %w(Caller Callee Calls)
            data.each do |p|
              csv << p.values_at(:source, :target, :count)
            end
          end
          render :text => str, :format => :csv
        end
      end
    end

    def call_graph
      render :layout => false
    end

    def js_exception_types
      redirect_on_empty_dataset and return
      @title = "Logged JavaScript Exceptions"
      @totals = Totals.new(@db, ["js_exceptions"], @page.blank? ? 'all_pages' : @page)
      @minutes = Minutes.new(@db, ["js_exceptions"], @page, @totals.page_names, 2)
    end

    def enlarged_plot
      redirect_on_empty_dataset and return
      @resources, @js_data, @js_events, @js_max, @request_counts, @gc_time, @js_zoom = @dataset.plot_data
    end

    def request_time_distribution
      redirect_on_empty_dataset and return
      @resources = Logjam::Resource.time_resources
      @dataset.get_data_for_distribution_plot(:request_time)
      @xmin = 100
      @xlabel = "Request time"
      render 'quants_plot'
    end

    def allocated_objects_distribution
      redirect_on_empty_dataset and return
      @resources = Logjam::Resource.memory_resources
      @dataset.get_data_for_distribution_plot(:allocated_objects)
      @xmin = 10000
      @xlabel = "Allocated objects"
      render 'quants_plot'
    end

    def allocated_size_distribution
      redirect_on_empty_dataset and return
      @resources = Logjam::Resource.memory_resources
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

    def database_information
      respond_to do |format|
        format.json do
          info = database_info.to_hash
          info[:databases].each do |h|
            h[:date] =~ /\A(\d+)-(\d+)-(\d+)\z/
            h[:totals] = "#{request.base_url}/#{$1}/#{$2}/#{$3}/index.json?app=#{h[:app]}&env=#{h[:env]}"
          end
          render :json => Oj.dump(info, :mode => :compat)
        end
      end
    end

    private

    def database_info
      @database_info ||= Logjam::DatabaseInfo.new
    end

    def default_date
      (database_info.days(params[:app], params[:env]).first || Date.today).to_date
    end

    def get_app_env
      @apps ||= database_info.apps
      @default_app ||= database_info.default_app
      last_app = session[:last_app]
      if last_app && @apps.include?(last_app) && !params[:app]
        @app = params[:app] = last_app
      else
        @app ||= (params[:app] || @default_app)
      end
      session[:last_app] = @app
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
      params[:interval] ||= FilteredDataset::DEFAULTS[:interval]
      params[:time_range] ||= 'date'
      @plot_kind = Resource.resource_type(params[:resource])
      @attributes = Resource.resources_for_type(@plot_kind)
      @collected_resources = Totals.new(@db).collected_resources
      @page = params[:page].to_s
    end

    def dataset_from_params(strip_namespace = false)
      prepare_params
      @dataset = FilteredDataset.new(
        :date => @date,
        :app => @app,
        :env => @env,
        :interval => params[:interval].to_i,
        :page => strip_namespace ? (@page.to_s).sub(/\A::/,'') : (@page.blank? ? '::' : @page),
        :plot_kind => @plot_kind,
        :resource => params[:resource] || :total_time,
        :collected_resources => @collected_resources,
        :grouping => params[:grouping],
        :grouping_function => (params[:grouping_function] || :avg).to_sym,
        :start_minute => params[:start_minute].to_i,
        :end_minute => params[:end_minute].to_i)
    end

    def redirect_on_empty_dataset(strip_namespace = false)
      dataset_from_params(strip_namespace)
      if @dataset.empty? && !@dataset.top_level? && !request.referer.to_s.include?("app=#{@app}")
        new_params = FilteredDataset.clean_url_params(params.merge(:page => '',
                                                                   :default_app => @default_app,
                                                                   :default_env => @default_env))
        redirect_to new_params
        return true
      else
        return false
      end
    end

    def redirect_to_clean_url
      return if request.format.to_s =~ /json/
      get_app_env
      py, pm, pd = params.values_at(:year, :month, :day).map(&:to_i)
      dd = default_date
      selected_date = dd.to_s(:db) if params[:auto_refresh] == "1" && (dd.year != py || dd.month != pm || dd.day != pd)
      selected_date ||= dd.to_s(:db) unless (params[:year] && params[:month] && params[:day])
      if selected_date.to_s =~ /\A(\d\d\d\d)-(\d\d)-(\d\d)\z/ || params[:page] == '::'
        new_params = FilteredDataset.clean_url_params(
          :auto_refresh => params[:auto_refresh] == "1" ? "1" : nil,
          :default_app => @default_app, :default_env => @default_env,
          :controller => params[:controller], :action => params[:action],
          :year => $1, :month => $2, :day => $3, :interval => params[:interval],
          :start_minute => params[:start_minute], :end_minute => params[:end_minute],
          :app => params[:app], :env => params[:env],
          :page => params[:page].to_s.sub(/\A::/,''), :response => params[:response],
          :resource => params[:resource],
          :sort => params[:sort], :group => params[:group], :filter => params[:filter],
          :offset => params[:offset], :error_type => params[:error_type],
          :grouping => params[:grouping], :grouping_function => params[:grouping_function])
        redirect_to new_params
      end
    end

    def print_params
      # p params
      # p request.format
    end

    def verify_app_env
      get_app_env
      unless @apps.include?(@app)
        msg = "Application '#{@app}' doesn't exist."
        respond_to do |format|
          format.html { render :text => msg, :status => 404 }
          format.json { render :json => {:error => msg}, :status => 404 }
        end
        return
      end
      unless @envs.include?(@env)
        msg = "Environment '#{@env}' doesn't exist for Application '#{@app}'."
        respond_to do |format|
          format.html { render :text => msg, :status => 404 }
          format.json { render :json => {:error => msg}, :status => 404 }
        end
        return
      end
    end

    def allow_cross_domain_ajax
      response.headers['Access-Control-Allow-Origin'] = '*'
    end

  end
end

# -*- coding: utf-8 -*-
require 'csv'
module Logjam

  class LogjamController < ApplicationController
    before_action :permit_params
    before_action :verify_date
    before_action :redirect_to_clean_url, :except => [:live_stream, :auto_complete_for_controller_action_page, :auto_complete_for_applications_page]
    before_action :verify_app_env, :except => [:call_relationships, :call_graph]
    before_action :print_params if Rails.env=="development"
    after_action :allow_cross_domain_ajax

    rescue_from Mongo::Error::NoServerAvailable, :with => :render_no_connection

    def auto_complete_for_controller_action_page
      respond_to do |format|
        format.json do
          params[:page] = params.delete(:query)
          prepare_params
          show_modules = [":", "::"].include?(@page)
          re = show_modules ? /^::/ : /#{@page}/i
          pages = Totals.new(@db).page_names.select {|name| name =~ re && name != 'all_pages'}
          pages.collect!{|p| p.gsub(/^::/,'')}
          completions = pages.sort  # [0..34]
          render :json => {query: params[:page], suggestions: completions}
        end
      end
    end

    def auto_complete_for_applications_page
      respond_to do |format|
        format.json do
          suggestions = @apps.select{|a| a.start_with?(params[:query]) }
          render :json => {query: params[:query], suggestions: suggestions }
        end
      end
    end

    def index
      respond_to do |format|
        format.html do
          redirect_on_empty_dataset and return
          @resources, @js_data, @js_events, @js_max, @request_counts, @lines, @js_zoom = @dataset.plot_data(@section)
          if @section == :frontend
            render :template => "logjam/logjam/frontend_overview"
          end
        end
        format.json do
          prepare_params
          pages, events = fetch_json_data_for_index(@db, @page)
          render :json => Oj.dump({:pages => pages, :events => events})
        end
      end
    end

    def fetch_json_data_for_index(db, page, options = params)
      options = options.merge(:app => @app, :env => @env)
      resources = Resource.all_resources + %w(apdex papdex xapdex response severity exceptions js_exceptions)
      stream = Logjam.streams["#{options[:app]}-#{options[:env]}"]
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

    def events
      respond_to do |format|
        format.html do
          redirect_on_empty_dataset and return
          @events = Events.new(@db).events
          @title = "Notifications"
        end
        format.json do
          prepare_params
          events = Events.new(@db).events
          render :json => Oj.dump(events)
        end
      end
    end

    def history
      respond_to do |format|
        format.html do
          dataset_from_params
        end
        format.json do
          prepare_params
          data = History.new(@db, @app, @env, @page).data
          # logger.debug data.inspect
          render :json => Oj.dump(data)
        end
      end
    end

    def leaders
      redirect_on_empty_dataset and return
      resources = %w(apdex papdex xapdex severity exceptions total_time)
      databases = DatabaseManager.get_cached_databases(:env => @env, :date => @date.to_formatted_s(:db))
      @applications = []

      databases.each do |db_name|
        db = Logjam.connection_for(db_name).use(db_name).database
        Logjam.db_name_format =~ db_name && (application = $1)
        stream = Logjam.streams["#{application}-#{@env}"]
        filter = stream.frontend_page

        pages = Totals.new(db, resources, '').pages(:order => :apdex, :limit => 100_000, :filter => filter)
        next unless pages.size > 0
        summary = pages.shift
        summary.page = "__summary__"
        while p = pages.shift
          summary.add(p)
        end

        papdex = summary.apdex_score(:page)
        xapdex = summary.apdex_score(:ajax)
        next if papdex.nan? && xapdex.nan? && params[:showall] != "1"
        papdex = "-" if papdex.nan?
        xapdex = "-" if xapdex.nan?

        @applications << {
            :application => application,
            :requests => summary.count,
            :apdex => summary.apdex_score(:backend),
            :papdex => papdex,
            :xapdex => xapdex,
            :errors => summary.error_count,
            :warnings => summary.warning_count,
            :exceptions => summary.exception_count,
        }
      end
      @applications.sort_by!{|a| -a[:apdex] }
      # @applications.each do |a|
      #   %i[apdex papdex xapdex].each do |k|
      #     if (v = a[k]).is_a?(Numeric)
      #       a[k] = (v*100.0).floor/100.0
      #     end
      #   end
      # end
      respond_to do |format|
        format.html
        format.json do
          render :json => Oj.dump(@applications)
        end
        format.csv do
          str = CSV.generate(:col_sep => ';') do |csv|
            csv << %w(Pos Application Backend-Apdex Page-Apdex Ajax-Apdex Requests Errors Exceptions)
            @applications.each_with_index do |p,i|
              csv << ([i+1] + p.values_at(:application, :apdex, :papdex, :xapdex, :requests, :errors, :exceptions))
            end
          end
          send_data str, :filename => "leaders.csv"
        end
      end
    end

    def user_agents
      redirect_on_empty_dataset and return
      agent_collection = Agents.new(@db)
      @summary = agent_collection.summary
      respond_to do |format|
        format.html do
          @limit = 100
          @agents = agent_collection.find(limit: @limit)
        end
        format.json do
          agents = agent_collection.find
          render :json => Oj.dump(agents)
        end
        format.csv do
          agents = agent_collection.find(select: Agents::BACKEND)
          str = Agents.array_to_csv(agents)
          send_data str, :filename => "user_agents_#{@app}.csv"
        end
      end
    end

    def show
      redirect_on_empty_dataset and return
      logjam_request_id = [@app, @env, params[:id]].join('-')
      @js_exceptions = Logjam::JsExceptions.new(@db).find_by_request(logjam_request_id)
      @request_id = params[:id]
      @request = Requests.new(@db).find(@request_id)
      respond_to do |format|
        format.html do
          unless @request || @js_exceptions.present?
            render :file => "#{Rails.root}/public/404.html", :status => :not_found
          end
          # HACK: remove :id from params before generating any urls to avoid above 404 when changing app
          params.delete(:id)
        end
        format.json do
          render :json => Oj.dump(@request||["NOT FOUND"])
        end
      end
    end

    def errors
      redirect_on_empty_dataset and return
      respond_to do |format|
        format.html do
          @page_size = 25
          offset = params[:offset].to_i
          eselector = nil
          @events = Events.new(@db).combined_events
          case params[:error_type]
          when "internal"
            @title = "Internal Server Errors"
            qopts = { :response_code => 500 }
            @error_count = @dataset.response_codes[500]
            @resources = %w(response)
            eselector = ->(minutes) { minutes.response["500"] }
          when "exceptions"
            @title = "Requests with exception «#{params[:exception]}»"
            qopts = { :exceptions => params[:exception] }
            @error_count = @dataset.exceptions[params[:exception]]
            @resources = %w(exceptions)
            eselector = ->(minutes) { minutes.exceptions[params[:exception]] }
          when "soft_exceptions"
            @title = "Requests with exception «#{params[:exception]}» logged (log-level below ERROR)"
            qopts = { :soft_exceptions => params[:exception] }
            @error_count = @dataset.soft_exceptions[params[:exception]]
            @resources = %w(soft_exceptions)
            eselector = ->(minutes) { minutes.soft_exceptions[params[:exception]] }
          else
            severity, @title, @error_count =
                              case params[:error_type]
                              when "logged_warning" then [2, "Logged Warnings", @dataset.logged_error_count(2)]
                              when "logged_error"; then [3, "Logged Errors", @dataset.logged_error_count(3)]
                              when "logged_fatal"; then [4, "Logged Fatal Errors", @dataset.logged_error_count(4)]
                              else [3, "Logged Errors", @dataset.logged_error_count(3)]
                              end
            @resources = %w(severity)
            qopts = { :severity => severity }
            eselector = ->(minutes) { minutes.severity_above(severity.to_s) }
          end
          totals = Totals.new(@db, @resources, @page.blank? ? 'all_pages' : @page)
          minutes = Minutes.new(@db, @resources, @page, totals.page_names, 2)
          @timeline = eselector.call(minutes)
          qopts.merge!(:limit => @page_size, :skip => offset)
          if (restricted = params.include?(:start_minute) || params.include?(:end_minute))
            qopts[:start_minute] = params[:start_minute].to_i
            qopts[:end_minute] = params[:end_minute].to_i
          end
          q = Requests.new(@db, "minute", @page, qopts)
          @requests = q.all
          @error_count = q.count if restricted
          @page_count = (@error_count.to_f/@page_size).ceil
          @current_page = offset/@page_size + 1
          @last_page = @page_count
          @last_page_offset = @error_count/@page_size*@page_size
          @next_page_offset = offset + @page_size
          @previous_page_offset = [offset - @page_size, 0].max
          @action_name = "errors"
        end
      end
    end

    def js_exceptions
      respond_to do |format|
        format.html do
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
          @page_count = (@error_count.to_f/@page_size).ceil
          @current_page = offset/@page_size + 1
          @last_page = @page_count
          @last_page_offset = @error_count/@page_size*@page_size
          @next_page_offset = offset + @page_size
          @previous_page_offset = [offset - @page_size, 0].max
        end
      end
    end

    def response_codes
      respond_to do |format|
        format.html do
          redirect_on_empty_dataset and return
          @page_size = 25
          @page = params[:page]
          if params[:above].present?
            @response_code = params[:above].to_i
          else
            @response_code = params[:response_code].to_i
          end
          @show_code = true
          if params[:above].present? && @response_code == 0
            @title = "Requests"
            @error_count = @dataset.stored_requests
            @show_code = false
          elsif params[:above].present? && @response_code >= 500
            @title = "Requests with response code above #{@response_code}"
            @error_count = @dataset.response_codes_above(@response_code)
          elsif params[:above].present? && @response_code >= 400
            @title = "Requests with response code in the range #{@response_code} to 499"
            @error_count = @dataset.response_codes_in_range(@response_code..499)
          else
            @title = "Requests with response code #{@response_code}"
            @error_count = @dataset.response_codes[@response_code] || 0
          end
          @sampling_rate_400s = @stream.sampling_rate_400s if (400..499).include?(@response_code)
          # TODO: this is way to expensive to calculate so we just approximate it.
          # We should store the actual count of stored requests in mongo.
          if @response_code > 0 && @response_code < 500 && @sampling_rate_400s && @sampling_rate_400s < 1
            @stored_error_count = @sampling_rate_400s * @error_count
            @approximated = true
            @skip_last = true
          else
            @stored_error_count = @error_count
            @skip_last = false
          end
          resources = %w(response)
          totals = Totals.new(@db, resources, @page.blank? ? 'all_pages' : @page)
          minutes = Minutes.new(@db, resources, @page, totals.page_names, 2)
          if params[:above].present? && @response_code >= 500
            @timeline = minutes.response_above(@response_code)
          elsif params[:above].present? && @response_code >= 400
            @timeline = minutes.response_in_range(@response_code..499)
          else
            @timeline = minutes.response[@response_code]
          end
          qopts = { :response_code => @response_code, :limit => @page_size, :skip => params[:offset].to_i, :above => params[:above].present? }
          if params.include?(:starte_minute) || params.include?(:end_minute)
            qopts[:start_minute] = params[:start_minute].to_i
            qopts[:end_minute] = params[:end_minute].to_i
          end
          q = Requests.new(@db, "minute", @page, qopts)
          @requests = q.all
          offset = params[:offset].to_i
          @stored_error_count ||= @error_count
          @page_count = (@stored_error_count.to_f/@page_size).ceil
          @current_page = offset/@page_size + 1
          @last_page = @page_count
          @last_page_offset = @stored_error_count/@page_size*@page_size
          @next_page_offset = offset + @page_size
          @previous_page_offset = [offset - @page_size, 0].max
          @action_name = "response_codes"
          @events = Events.new(@db).combined_events
          render "errors"
        end
      end
    end

    def totals_overview
      respond_to do |format|
        format.html do
          redirect_on_empty_dataset(true) and return
          @dataset.limit = 100_000
        end
      end
    end

    def request_overview
      respond_to do |format|
        format.html do
          redirect_on_empty_dataset and return
          @page_size = 25
          offset = params[:offset].to_i
          @dataset.limit = @page_size
          @dataset.offset = offset
          @requests = @dataset.do_the_query(@section)
          @request_count = @dataset.stored_metrics
          @page_count = (@request_count.to_f/@page_size).ceil
          @current_page = offset/@page_size + 1
          @last_page = @page_count
          @last_page_offset = @request_count/@page_size*@page_size
          @next_page_offset = offset + @page_size
          @previous_page_offset = [offset - @page_size, 0].max
          @skip_last = true
          resources = [ @dataset.resource ]
          totals = Totals.new(@db, resources, @page.blank? ? 'all_pages' : @page)
          minutes = Minutes.new(@db, resources, @page, totals.page_names, 2)
          @timeline = @section == :frontend ? minutes.counts["frontend_count"] : minutes.counts["count"]
        end
      end
    end

    def error_overview
      respond_to do |format|
        format.html do
          redirect_on_empty_dataset and return
          @title = "Problem Overview"
          @resources = %w(exceptions soft_exceptions js_exceptions severity response)
          @totals = Totals.new(@db, @resources, @page.blank? ? 'all_pages' : @page)
          @minutes = Minutes.new(@db, @resources, @page, @totals.page_names, 2)
          @events = Events.new(@db).combined_events
        end
      end
    end

    def response_code_overview
      respond_to do |format|
        format.html do
          redirect_on_empty_dataset and return
          @title = "Response Code Overview"
          @resources = %w(response)
          @totals = Totals.new(@db, @resources, @page.blank? ? 'all_pages' : @page)
          @minutes = Minutes.new(@db, @resources, @page, @totals.page_names, 2)
        end
      end
    end

    def apdex_overview
      respond_to do |format|
        format.html do
          redirect_on_empty_dataset and return

          if @section == :frontend
            case params[:resource]
            when 'page_time'
              @resources = %w(papdex)
              resource = 'page_time'
            when 'ajax_time'
              @resources = %w(xapdex)
              resource = 'ajax_time'
            when 'frontend_time'
              @resources = %w(fapdex)
              resource = 'frontend_time'
            else
              resource = 'page_time'
            end
          else
            resource = 'total_time'
            @resources = %w(apdex)
          end
          @title = "Apdex Overview «#{resource.humanize}»"

          @totals = Totals.new(@db, @resources, @page.blank? ? 'all_pages' : @page)
          @minutes = Minutes.new(@db, @resources, @page, @totals.page_names, 2)
        end
      end
    end

    def exceptions
      respond_to do |format|
        format.html do
          redirect_on_empty_dataset and return
          @title = "Logged Exceptions"
          @totals = Totals.new(@db, ["exceptions"], @page.blank? ? 'all_pages' : @page)
          @minutes = Minutes.new(@db, ["exceptions"], @page, @totals.page_names, 2)
          @soft_title = "Logged Soft-Exceptions (below log-level = Error)"
          @soft_totals = Totals.new(@db, ["soft_exceptions"], @page.blank? ? 'all_pages' : @page)
          @soft_minutes = Minutes.new(@db, ["soft_exceptions"], @page, @totals.page_names, 2)
        end
      end
    end

    def callers
      redirect_on_empty_dataset and return
      params[:sort] ||= 'count'
      params[:group] ||= 'module'
      params[:kind] ||= 'callers'
      head(:bad_request) unless %w(callers senders).include?(params[:kind])
      @totals = Totals.new(@db, [params[:kind]], @page)
      @callers = @totals.send(params[:kind].to_sym)
      transform = get_relationship_key(params[:group])
      @callers = @callers.each_with_object(Hash.new(0)){|(k,v),h| h[transform.call(k)] += v}
      respond_to do |format|
        format.html do
          @title = params[:kind] == 'senders' ? "Message Senders" : "API Callers"
          @callers =
            case params[:sort]
            when 'name'
              @callers.sort_by{|k,v| k}
            else
              @callers.sort_by{|k,v| -v}
            end
          @call_count = @callers.blank? ? 0 : @callers.map(&:second).sum
          @request_count = @totals.count
          @caller_minutes = Minutes.new(@db, [params[:kind]], @page, @totals.page_names, 2).send(params[:kind])
          minutes = Hash.new{|h,k| h[k] = Hash.new(0)}
          @caller_minutes = @caller_minutes.each_with_object(minutes) do |(k,h),calls|
            callee = transform.call(k)
            counts = calls[callee]
            h.each {|m,c| counts[m] += c}
          end
        end
        format.json do
          all_pages = @page == 'all_pages' || @page.to_s.empty?
          page = all_pages ? '::' : @page.to_s
          page.sub!(/\A::/,'')
          app = page == '' ? @app : "#{@app}::"
          target = "#{app}#{page}"
          array = @callers.map{|k,v| {source: k.sub('@','::'), target: target, count: v}}
          render :json => Oj.dump(array)
        end
      end
    end

    def get_relationship_key(group)
      # The importer replaces dots in the application-action pair with the
      # unicode character '∙', so we need to reverse this transformation here.
      # The key depends on how to group the results: either by 'application',
      # 'module', or 'action'.
      case group
      when 'module'
        ->(k) do
          app, action = k.gsub('∙','.').split('@',2)
          # extract the module
          m = action.split(/(::)|#/)[0]
          # TODO: dirty hack (but for what?)
          m = app.capitalize if m =~ /Controller\z/
          "#{app}@#{m}"
        end
      when 'application'
        ->(k){ k.gsub('∙','.').split('@').first }
      else
        ->(k){ k.gsub('∙','.') }
      end
    end
    private :get_relationship_key

    def get_relationship_data(group: nil, filter: nil, sort: nil, kind: 'callers')
      # compute a map from caller, callee pairs to how often the call happened
      filter_regexp = /#{filter}/i unless filter.blank?
      transform = get_relationship_key(group)
      data = Hash.new(0)
      databases = DatabaseManager.get_cached_databases(:env => @env, :date => @date.to_formatted_s(:db))
      databases.each do |db_name|
        begin
          stream = Logjam.stream_for(db_name)
          db = Logjam.connection_for(db_name).use(db_name).database
          relationships = Totals.new(db).relationships(stream.app, kind)
          relationships.each do |callee_or_consumer, callers_or_senders|
            callee_or_consumer = transform.call(callee_or_consumer)
            callers_or_senders.each do |caller_or_sender, count|
              caller_or_sender = transform.call(caller_or_sender)
              next if filter_regexp && "#{caller_or_sender},#{callee_or_consumer}" !~ filter_regexp
              data[[caller_or_sender, callee_or_consumer]] += count.to_i
            end
          end
        rescue => e
          logger.error e
        end
      end
      # convert data into an array and sort it
      data = data.map{|p,c| {source: p[0].sub('@','::'), target: p[1].sub('@','::'), count: c}}
      case sort
      when 'caller', 'sender' then data.sort_by!{|p| [p[:source],p[:target]]}
      when 'callee', 'consumer' then data.sort_by!{|p| [p[:target],p[:source]]}
      when 'count'  then data.sort_by!{|p| -p[:count]}
      end
      data
    end
    private :get_relationship_data

    def call_relationships
      redirect_on_empty_dataset and return
      params[:group] ||= 'module'
      params[:sort] ||= 'caller'
      params[:kind] ||= 'callers'
      # only filter data when explicitly requested
      filter = params[:filter_data].to_s == '1' ? params[:filter].to_s : ''
      data = get_relationship_data(group: params[:group], filter: filter,
                                   sort: params[:sort], kind: params[:kind])
      @relationship_name, @source_name, @target_name, @counter_name =
         case params[:kind]
         when 'callers' then ["Call relationships", "Caller", "Callee", "#Calls"]
         when 'senders' then ["Message consumption", "Sender", "Consumer", "#Messages"]
         else ["Unknown relationship" , "Source", "Target", "Count"]
         end
      respond_to do |format|
        format.html do
          @title = "#{@relationship_name} across all applications"
          @data = data
        end
        format.json do
          render :json => Oj.dump(data)
        end
        format.csv do
          str = CSV.generate(:col_sep => ';') do |csv|
            csv << [@source_name, @target_name, @counter_name]
            data.each do |p|
              csv << p.values_at(:source, :target, :count)
            end
          end
          send_data str, :filename => "#{@relationship_name.downcase.gsub(' ', '_')}.csv"
        end
      end
    end

    def call_graph
      respond_to do |format|
        format.html do
          render :layout => false
        end
      end
    end

    def js_exception_types
      respond_to do |format|
        format.html do
          redirect_on_empty_dataset and return
          @title = "Logged JavaScript Exceptions"
          @totals = Totals.new(@db, ["js_exceptions"], @page.blank? ? 'all_pages' : @page)
          @minutes = Minutes.new(@db, ["js_exceptions"], @page, @totals.page_names, 2)
        end
      end
    end

    def enlarged_plot
      respond_to do |format|
        format.html do
          redirect_on_empty_dataset and return
          @resources, @js_data, @js_events, @js_max, @request_counts, @lines, @js_zoom = @dataset.plot_data(@section)
        end
      end
    end

    def request_time_distribution
      respond_to do |format|
        format.html do
          redirect_on_empty_dataset and return
          @xlabel = "Response time (ms)"
          if @section == :frontend
            @resources = Logjam::Resource.frontend_resources - %w(frontend_time)
            @dataset.get_data_for_distribution_plot(:frontend_time)
            @xmin = 1
            @title = "Frontend Response Time Distribution (ms)"
          else
            @resources = Logjam::Resource.time_resources.reverse
            @dataset.get_data_for_distribution_plot(:request_time)
            @xmin = 1
            @title = "Backend Response Time Distribution (ms)"
          end
          render 'quants_plot'
        end
      end
    end

    def allocated_objects_distribution
      respond_to do |format|
        format.html do
          redirect_on_empty_dataset and return
          @resources = Logjam::Resource.memory_resources
          @dataset.get_data_for_distribution_plot(:allocated_objects)
          @xmin = 1
          @xlabel = "Allocated objects"
          @title = "Allocated Objects Distribution"
          render 'quants_plot'
        end
      end
    end

    def allocated_size_distribution
      respond_to do |format|
        format.html do
          redirect_on_empty_dataset and return
          @resources = Logjam::Resource.memory_resources
          @dataset.get_data_for_distribution_plot(:allocated_bytes)
          @xmin = 1024
          @xlabel = "Allocated memory"
          @title = "Allocated Memory Distribution (bytes)"
          render 'quants_plot'
        end
      end
    end

    def heatmaps
      @title = "Heatmaps"
      @resources = %w(total_time page_time ajax_time)
      respond_to do |format|
        format.html do
          redirect_on_empty_dataset and return
          interval = params[:interval].to_i
          histograms = Histograms.new(@db, @resources, @page)
          # logger.debug "PAGE NAMES: #{histograms.page_names}"
          # logger.debug "MODULES: #{histograms.modules}"
          @histograms = histograms.histograms(interval)
          # logger.debug "HISTOGRAMS: #{@histograms.inspect}"
        end
      end
    end

    def live_stream
      respond_to do |format|
        format.html do
          redirect_on_missing_date_params and return
          redirect_on_empty_dataset and return
          @resources = (Logjam::Resource.time_resources-%w(total_time gc_time)) & @collected_resources
          @socket_url = Logjam.web_socket_uri(request)
          @key = params[:page].to_s
          @key = "all_pages" if @key.blank? || @key == "::"
          @key = @key.sub(/^::/,'').downcase
        end
      end
    end

    def database_information
      dataset_from_params
      @collstats = Logjam.get_collection_info(@db)
      respond_to do |format|
        format.html do
          @collstats.sort_by!{|_,stats| -stats[:size]}
        end
        format.json do
          render :json => Oj.dump(@collstats)
        end
      end
    end

    private

    def get_app_env
      @apps ||= Logjam.apps
      @envs ||= Logjam.envs
      @default_db ||=
        begin
          if default_db = DatabaseManager.default_database
            @default_app, @default_env, default_date = Logjam.extract_db_params(default_db)
            @default_date = Date.parse(default_date) rescue Date.today
          else
            @default_app, @default_env, @default_date = @apps.first, @envs.first, Date.today
            default_db = Logjam.db_name(@default_date, @default_app, @default_env)
          end
          default_db
        end
      last_app = session[:last_app]
      if last_app && @apps.include?(last_app) && !params[:app]
        @app = params[:app] = last_app
      else
        @app ||= (params[:app] || @default_app)
      end
      session[:last_app] = @app
      @env ||= (params[:env] ||= @default_env)
      @only_one_app = @apps.size == 1
      @only_one_env = @envs.size == 1
      @stream = Logjam.streams["#{@app}-#{@env}"]
    end

    def date_from_params
       params[:year].blank? ? nil : "#{params[:year]}-#{params[:month]}-#{params[:day]}".to_date
    end

    def get_date
      get_app_env
      @date = date_from_params
      @date ||= @default_date
      @days = DatabaseManager.get_cached_dates(:app => @app, :env => @env)
    end

    def permit_params
      # TODO: fix this security hole
      params.permit!
    end

    def prepare_params
      get_date
      begin
        @db = Logjam.db(@date, @app, @env)
      rescue
        # TODO: deal with no defined stream being defined and no databases in the UI
        if session[:last_app]
          session[:last_app] = nil
          redirect_to "/"
          return false
        else
          raise
        end
      end

      params[:section] ||= 'backend'
      params[:start_minute] ||= FilteredDataset::DEFAULTS[:start_minute]
      params[:end_minute] ||= FilteredDataset::DEFAULTS[:end_minute]
      params[:resource] ||= params[:section] == "frontend" ? Resource.default_resource(:frontend) : FilteredDataset::DEFAULTS[:resource]
      params[:grouping] ||= FilteredDataset::DEFAULTS[:grouping]
      params[:grouping_function] ||= FilteredDataset::DEFAULTS[:grouping_function]
      params[:interval] ||= FilteredDataset::DEFAULTS[:interval]
      params[:auto_refresh] ||= '0'
      params[:time_range] ||= 'date'
      @section = params[:section] == "frontend" ? :frontend : :backend
      params[:scale] ||= 'logarithmic'

      if @section == :frontend && !(Resource.frontend_resources.include?(params[:resource]) || Resource.dom_resources.include?(params[:resource]))
        redirect_to params.to_hash.merge(:resource => 'page_time', :section => 'frontend')
        return false
      elsif @section == :backend && !Resource.backend_resources.include?(params[:resource])
        redirect_to params.to_hash.merge(:resource => 'total_time', :section => 'backend')
        return false
      end

      @plot_kind = Resource.resource_type(params[:resource])
      @attributes = Resource.resources_for_type(@plot_kind)
      @page = params[:page].to_s
      @collected_resources = Totals.new(@db).collected_resources
    end

    def dataset_from_params(strip_namespace = false)
      return false unless prepare_params
      @dataset = FilteredDataset.new(@stream,
        :date => @date,
        :app => @app,
        :env => @env,
        :section => @section,
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
      dataset_from_params(strip_namespace) or return true
      logger.debug "DATASET BE EMPTY = #{@dataset.empty?}"
      if @dataset.empty?
        if !@dataset.top_level? && !request.referer.to_s.include?("app=#{@app}")
          new_params = FilteredDataset.clean_url_params(params.merge(:page => ''), params)
          redirect_to new_params.to_hash
        else
          @collected_resources = []
          @warning = "No data found for application «#{@app}» in environment «#{@env}» on #{@date.to_formatted_s(:long_ordinal)}."
          render "warning", status: 200
        end
        return true
      elsif @section == :frontend && !@dataset.has_frontend?
        redirect_to params.to_hash.merge(:section => "backend")
        return true
      else
        return false
      end
    end

    def redirect_to_clean_url
      return if request.format.to_s =~ /json/
      get_app_env
      py, pm, pd = params.values_at(:year, :month, :day).map(&:to_i)
      dd = @default_date
      selected_date = dd.to_formatted_s(:db) if params[:auto_refresh] == "1" && (dd.year != py || dd.month != pm || dd.day != pd)
      selected_date ||= dd.to_formatted_s(:db) unless (params[:year] && params[:month] && params[:day])
      if selected_date.to_s =~ /\A(\d\d\d\d)-(\d\d)-(\d\d)\z/ || params[:page] == '::'
        new_params = FilteredDataset.clean_url_params({
          :auto_refresh => params[:auto_refresh] == "1" ? "1" : nil,
          :controller => params[:controller], :action => params[:action],
          :year => $1, :month => $2, :day => $3, :interval => params[:interval],
          :start_minute => params[:start_minute], :end_minute => params[:end_minute],
          :app => params[:app], :env => params[:env],
          :page => params[:page].to_s.sub(/\A::/,''), :response => params[:response],
          :resource => params[:resource],
          :sort => params[:sort], :group => params[:group], :filter => params[:filter],
          :exclude_response => params[:exclude_response],
          :offset => params[:offset], :error_type => params[:error_type],
          :scale => params[:scale],
          :grouping => params[:grouping], :grouping_function => params[:grouping_function]}, params)
        redirect_to new_params
      end
    end

    def redirect_on_missing_date_params
      redirect_to_clean_url if params[:year].blank? || params[:month].blank? || params[:day].blank?
    end

    def print_params
      # p params
      # p request.format
    end

    def render_no_connection
      @warning = "Could not connect to database server! Please try again later."
      @app ||= params[:app] || Logjam.fallback_app
      @env ||= params[:env] || Logjam.fallback_env
      @date ||= Date.today
      @days ||= [ @date ]
      @dataset = nil
      respond_to do |format|
        format.html { render "warning", :status => 500 }
        format.json { render :json => {:error => 'no database connection'}, :status => 500 }
      end
    end

    def verify_date
      get_date
      today = Date.today
      if @date > today || @date < today - Logjam.database_cleaning_threshold
        @warning = "No data found for application «#{@app}» in environment «#{@env}» on #{@date.to_s(:long_ordinal)}."
        respond_to do |format|
          format.html { render "warning", :status => 404 }
          format.json { render :json => {:error => @warning}, :status => 404 }
        end
      end
    end

    def verify_app_env
      get_app_env
      unless @apps.include?(@app)
        @warning = "Application «#{@app}» is not known to exist."
        @app = @default_app
        params[:app] = @app
        respond_to do |format|
          format.html { render "warning", :status => 404 }
          format.json { render :json => {:error => @warning}, :status => 404 }
        end
        return
      end
      unless @envs.include?(@env)
        @warning = "Environment «#{@env}» doesn't exist for application «#{@app}»."
        @env = @default_env
        params[:env] = @env
        respond_to do |format|
          format.html { render "warning", :status => 404 }
          format.json { render :json => {:error => @warning}, :status => 404 }
        end
        return
      end
      unless @stream
        @warning = "No data found for application «#{@app}» in environment «#{@env}» on #{@date.to_s(:long_ordinal)}."
        respond_to do |format|
          format.html { render "warning", :status => 404 }
          format.json { render :json => {:error => @warning}, :status => 404 }
        end
      end
    end

    def allow_cross_domain_ajax
      response.headers['Access-Control-Allow-Origin'] = '*' if Logjam.allow_cross_domain_ajax
    end

    def default_url_options
      defaults = {
        app: params[:app].presence || @default_app,
        env: params[:env].presence || @default_env,
      }
      (super() || {}).merge(defaults)
    end
  end
end

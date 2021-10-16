# -*- coding: utf-8 -*-
module Logjam

  # Methods added to this helper will be available to all templates in the application.
  module LogjamHelper
    def extract_minute_from_iso8601(iso_string)
      60 * iso_string[11..12].to_i + iso_string[14..15].to_i
    end

    def logjam_header_request_id
      if rid = LogjamAgent.request.try(:id)
        tag(:meta, :name => "logjam-request-id", :content => rid)
      end
    end

    def logjam_header_action
      if action = LogjamAgent.request.try(:action)
        tag(:meta, :name => "logjam-action", :content => action)
      end
    end

    def logjam_header_timings_collector
      collector_url = Logjam.frontend_timings_collector || "#{request.protocol}#{request.host}:#{Logjam.frontend_timings_collector_port}"
      tag(:meta, :name => "logjam-timings-collector", :content => collector_url)
    end

    def page_title
      title = "Logjam"
      title += " | #{@app}-#{@env}" if @app.present? && @env.present?
      if @page.present?
        namespace = @page.split("::").first
        title += " | #{namespace}" if namespace.present?
      end
      title += " | #{@request_id}" if defined?(@request_id)
      title
    end

    def frontend?
      @section == :frontend
    end

    def backend?
      @section == :backend
    end

    def default_header_parameters
      FilteredDataset::DEFAULTS.merge(:time_range => 'date', :auto_refresh => '0', :scale => 'logarithmic', :error_type => 'logged_error')
    end

    def date_to_params(date)
      {
        :day => sprintf("%02d", date.day),
        :month => sprintf("%02d", date.month),
        :year => sprintf("%04d", date.year)
      }
    end

    def home_url
      url_for(params.except(:id).merge(action: 'index'))
    end

    def history_url
      url_for(params.except(:id).merge(:action => 'history'))
    end

    def self_url
      url_for(params)
    end

    def auto_complete_url_for_action_page
      url_for(params.slice(:year, :month, :day, :app, :env).merge(:action => "auto_complete_for_controller_action_page", :format => :json))
    end

    def auto_complete_url_for_application_page
      url_for(params.slice(:year, :month, :day, :app, :env).merge(:action => "auto_complete_for_applications_page", :format => :json))
    end

    def collected_frontend_time_resources
      (Logjam::Resource.frontend_resources - %w[frontend_time]) & (@collected_resources || [])
    end

    def collected_dom_resources
      Logjam::Resource.dom_resources & (@collected_resources || [])
    end

    def collected_time_resources
      Logjam::Resource.time_resources & (@collected_resources || [])
    end

    def collected_call_resources
      Logjam::Resource.call_resources & (@collected_resources || [])
    end

    def collected_memory_resources
      Logjam::Resource.memory_resources & (@collected_resources || [])
    end

    def collected_heap_resources
      Logjam::Resource.heap_resources & (@collected_resources || [])
    end

    def collected_dom_resources
      Logjam::Resource.dom_resources & (@collected_resources || [])
    end

    def grouping_options
      options_for_select(Logjam::Resource.grouping_options, params[:grouping])
    end

    def resource_options
      options_for_select(Logjam::Resource.resource_options, params[:resource])
    end

    def grouping_functions
      options_for_select(Logjam::Resource.grouping_functions, params[:grouping_function])
    end

    def time_number(f)
      if f.to_f.nan?
        "NaN"
      else
        number_with_precision(f.to_f, :delimiter => ",", :separator => ".", :precision => 2)
      end
    end
    alias_method :float_number, :time_number

    def memory_number(f)
      if f.to_f.nan?
        "NaN"
      else
        number_with_precision(f.floor, :delimiter => ",", :separator => ".", :precision => 0)
      end
    end

    def integer_number(i)
      if i.to_f.nan?
        "NaN"
      else
        number_with_precision(i.to_i, :delimiter => ",", :precision => 0)
      end
    end

    def apdex_number(f)
      if !f.is_a?(Numeric)
        f.to_s
      elsif f.to_f.nan?
        "NaN"
      else
        number_with_precision((f.to_f*100).floor/100.0, :delimiter => ",", :separator => ".", :precision => 2)
      end
    end

    def callers_sorting_options
      %w(name count)
    end

    def callers_grouping_options
      %w(application module action)
    end

    def count_to_human(count, precision: 2)
      case
      when count.to_f.nan?
        "NaN"
      when count < 100_000
        integer_number(count)
      else
        "#{number_with_precision(count.to_f / 1_000_000, :precision => precision, :delimiter => ',')}M"
      end
    end

    def seconds_to_human(seconds)
      case
      when seconds.to_f.nan?
        "NaN"
      when seconds < 60
        "#{number_with_precision(seconds, :precision => 2, :delimiter => ',')}s"
      when seconds < 3600
        "#{number_with_precision(seconds / 60, :precision => 2, :delimiter => ',')}m"
      else
        "#{number_with_precision(seconds / 3600, :precision => 2, :delimiter => ',')}h"
      end
    end

    def minute_to_human(minute_of_day)
      "%02d:%02d" % minute_of_day.divmod(60)
    end

    def request_started_at(request)
      request["started_at"][11..18]
    rescue
      minute_to_human(request["minute"])
    end

    def distribution_kind(resource)
      case Resource.resource_type(resource)
      when :time, :frontend
        :request_time_distribution
      when :memory
        case resource
        when 'allocated_objects'
          :allocated_objects_distribution
        else
          :allocated_size_distribution
        end
      else
        nil
      end
    end

    def line_tags(line)
      logline = line.last.to_s.strip
      tags = []
      tags << "view"      if logline =~ /^Rendered/
      tags << "api"       if logline =~ /(^API|PerlBackend)/
      tags << "memcache"  if logline =~ /^DALLI/
      tags << "rest"      if logline =~ /(^REST|RESTApi)/
      tags.join(" ")
    end

    def clean_params(params)
      FilteredDataset.clean_url_params(params, self.params)
    end

    def clean_link_to(*args, &block)
      if block_given?
        options      = args[0] || {}
        html_options = args[1]
        cleaned_options = clean_params(params.merge(options))
        clean_link_to(capture(&block), cleaned_options, html_options)
      else
        name         = args[0]
        options      = args[1] || {}
        html_options = args[2]
        cleaned_options = clean_params(params.merge(options))
        link_to(name, cleaned_options, html_options)
      end
    end

    def clean_url_for(options)
      url_for(clean_params(params.merge(options)))
    end

    def sometimes_link_grouping_result(result, grouping, params)
      value = result.send(grouping)
      _scope, action = value.split('#')
      if value.length > 40
        if action.to_s.length > 25
          tooltip = value.gsub(/\A(.*)#/, "\u2026#")
        else
          tooltip = value
        end
      end
      ppage = params[:page]
      if grouping.to_sym == :page && ppage !~ /\AOthers/ && (ppage != @page || ppage =~ /^::/)
        params = params.merge(grouping => value)
        params[:page] = without_module(ppage) # unless @page == "::"
        params[:action] = "index"
        clean_link_to(value, params, :title => tooltip)
      else
        content_tag(:span, value, :class => 'dead-link', :title => tooltip)
      end
    end

    def apdex_section
      if @section == :frontend
        params[:resource] == 'ajax_time' ? :ajax : :page
      else
        :backend
      end
    end

    def sometimes_link_requests(result, grouping, options)
      if options.has_key?(:n)
        n = options.delete(:n)
      else
        n = number_with_delimiter(result.count(params[:resource]).to_i)
      end
      if :page == grouping.to_sym && result.page != "Others..."
        clean_link_to(n, options.merge(:action => "index"), :"data-tooltip" => "show requests")
      else
        n
      end
    end

    def sometimes_link_stddev(page, resource)
      stddev = page.stddev(resource)
      if stddev.to_f.finite?
        n = number_with_precision(stddev, :precision => 0 , :delimiter => ',')
      else
        n = stddev.to_s
      end
      if stddev > 0 && page.page != "Others..."
        params = { :app => @app, :env => @env, :page => without_module(page.page), :action => distribution_kind(resource) }
        clean_link_to(n, params, :"data-tooltip" => distribution_kind(resource).to_s.gsub(/_/,' '))
      else
        n
      end
    end

    def sometimes_link_all_pages(&block)
      if params[:grouping] == "page"
        clean_link_to(:action => "totals_overview", :page => @page, &block)
      elsif params[:grouping] == "request"
        clean_link_to(:action => "request_overview", :page => @page, &block)
      else
        capture(&block) if block_given?
      end
    end

    def sometimes_link_resource(resources, resource, html_options={}, &block)
      if resources.include?(params[:resource])
        capture(&block) if block_given?
      else
        clean_link_to({:resource => resource}, html_options, &block)
      end
    end

    def link_to_request(text, options)
      clean_link_to(text, options, :"data-tooltip" => "show request")
    end

    def sometimes_link_to_request(request_id)
      parts = request_id.split('-')
      oid = parts.pop
      env = parts.pop
      app = parts.join('-')
      if Logjam.stream_defined?(app, env) && oid.present? && Requests.exists?(@date, app, env, oid)
        params = { :app => app, :env => env, :action => "show", :id => oid }
        clean_link_to(request_id, params, :"data-tooltip" => "show request")
      else
        request_id
      end
    end

    def sometimes_link_errors(page)
      error_count = page.error_count
      warning_count = page.warning_count
      n = error_count + warning_count
      if n == 0
        ""
      elsif page.page == "Others..."
        "#{integer_number(error_count)}/#{integer_number(warning_count)}"
      else
        params = { :app => @app, :env => @env, :action => "errors", :page => without_module(page.page) }
        errors = error_count == 0 ? error_count :
          clean_link_to(count_to_human(error_count), params.merge(:error_type => "logged_error"), :class => "error data-tooltip-bottom-nose-right", :"data-tooltip" => "show errors")
        warnings = warning_count == 0 ? warning_count :
          clean_link_to(count_to_human(warning_count), params.merge(:error_type => "logged_warning"), :class => "warn data-tooltip-bottom-nose-right", :"data-tooltip" => "show warnings")
        raw "#{errors}/#{warnings}"
      end
    end

    def sometimes_link_400s(page)
      n = page.four_hundreds
      if n == 0
        "0"
      elsif page.page == "Others..."
        count_to_human(n)
      else
        params = { :app => @app, :env => @env, :action => "response_codes", :above => 400, :page => without_module(page.page) }
        link_to(count_to_human(n), params, :class => "warn", :"data-tooltip" => "show 400s")
      end
    end

    def sometimes_link_500s(page)
      n = page.five_hundreds
      if n == 0
        "0"
      elsif page.page == "Others..."
        count_to_human(n)
      else
        params = { :app => @app, :env => @env, :action => "response_codes", :above => 500, :page => without_module(page.page) }
        link_to(count_to_human(n), params, :class => "error", :"data-tooltip" => "show 500s")
      end
    end

    def sometimes_link_response_errors(page)
      n = page.five_hundreds + page.four_hundreds
      if n == 0
        ""
      else
        sometimes_link_500s(page) + "/" + sometimes_link_400s(page)
      end
    end

    def response_code_link_options(code, n)
      params = { :app => @app, :env => @env, :action => "response_codes", :page => @page }
      if n == 0 || code.to_s =~ /[1-3]xx\z/
        [nil, {}]
      else code.to_s =~ /xx\z/
        params[:above] = code.to_s.sub('xx', '00') unless code == "0xx"
        [ clean_url_for(params), {:tr_class => "clickable", :class => "error", :title => "show requests with response #{code}"}]
      end
    end

    def sometimes_link_response_code(code, n, force_link: false)
      text = memory_number(n)
      params = { :app => @app, :env => @env, :action => "response_codes", :page => @page }
      if n == 0 || (code.to_s =~ /[0-3]xx\z/ && !force_link)
        text
      elsif code.to_s =~ /xx\z/
        params[:above] = code.to_s.sub('xx', '00')
        if force_link
          clean_link_to(text, params, :class => "green", :"data-tooltip" => "show requests with response #{code}")
        else
          clean_link_to(text, params, :class => "error", :"data-tooltip" => "show requests with response #{code}")
        end
      elsif code.to_i < 400 && code.to_i > 0
        text
      else
        params[:response_code] = code
        clean_link_to(text, params, :class => "error", :"data-tooltip" => "show requests with response #{code}")
      end
    end

    def link_error_list(n, error_type, html_options={})
      page = (@page||'').gsub(/^::/,'')
      params = { :page => page, :action => "errors", :error_type => error_type }
      clean_link_to(integer_number(n), params, html_options)
    end

    def error_link_options(n, error_type, html_options)
      if n > 0
        page = (@page||'').gsub(/^::/,'')
        params = { :page => page, :action => "errors", :error_type => error_type }
        [ clean_url_for(params), html_options.merge(:class => "error", :tr_class => "clickable") ]
      else
        [ nil, {} ]
      end
    end

    def sometimes_link_error_list(n, error_type, html_options={})
      n == 0 ? integer_number(n) : link_error_list(n, error_type, html_options)
    end

    def exception_link_options(n, html_options)
      if n > 0
        page = (@page||'').gsub(/^::/,'')
        params = { :page => page, :action => "exceptions" }
        [ clean_url_for(params), html_options.merge(:class => "error", :tr_class => "clickable") ]
      else
        [ nil, {} ]
      end
    end

    def link_exception_list(n, html_options={})
      page = (@page||'').gsub(/^::/,'')
      params = { :page => page, :action => "exceptions" }
      clean_link_to(integer_number(n), params, html_options)
    end

    def sometimes_link_exception_list(n, html_options={})
      n == 0 ? integer_number(n) : link_exception_list(n, html_options)
    end

    def link_js_exception_list(n, html_options={})
      page = (@page||'').gsub(/^::/,'')
      params = { :page => page, :action => "js_exception_types", :section => :frontend }
      clean_link_to(integer_number(n), params, html_options)
    end

    def without_module(page)
      page.blank? ? page : page.sub(/^::(.)/){$1}
    end

    def sorted_by_grouping_function(gf)
      if params[:grouping_function].to_s == gf
        " sorted"
      else
        " "
      end
    end

    def html_attributes_for_grouping_function(gf, title)
      if gf.to_sym == @dataset.grouping_function
        %{class="sorted" title="sorted by #{title}"}
      else
        %{class="sortable" onclick="sort_by('#{gf}')" title="sort by #{title}"}
      end
    end

    def html_attributes_for_grouping(grouping)
      if params[:grouping] == grouping
        "class='active' onclick=\"view_grouping('#{grouping}')\""
      else
        "class='inactive' onclick=\"view_grouping('#{grouping}')\""
      end
    end

    def html_attributes_for_time_range(time_range)
      if params[:time_range] == time_range
        "class='active'"
      else
        "class='inactive' onclick=\"view_time_range('#{time_range}')\""
      end
    end

    def html_attributes_for_resource_type(resource_type)
      resource = Resource.default_resource(resource_type)
      section = Resource.section(resource)
      # TODO: add switch between resources (frontend|backend)
      if Resource.resource_type(params[:resource]) == resource_type.to_sym
        "class='active' onclick=\"view_resource('#{resource}', '#{section}')\""
      else
        "class='inactive' onclick=\"view_resource('#{resource}', '#{section}')\""
      end
    end

    def apdex_rating(v)
      case
      when v >= 0.94 then "excellent"
      when v >= 0.85 then "good"
      when v >= 0.7  then "fair"
      when v >= 0.5  then "poor"
      else "unacceptable"
      end
    end

    def truncated_apdex(v)
      sprintf "%.2f", (v * 100.0).floor / 100.0
    end

    def card_apdex_class(v)
      (!v.is_a?(Numeric) || v.to_f.nan? || v >= 0.94) ? "apdex-ok" : "apdex-fail"
    end

    def apdex_class(v, gf = params[:grouping_function])
      if gf == "apdex" && v.is_a?(Numeric) && !v.to_f.nan?
        card_apdex_class(v)
      else
        ""
      end
    end

    def page_percent(pages, page, resource)
      case gf = params[:grouping_function]
      when "apdex"
        page.apdex_score(resource).to_f * 100
      when "sum"
        div_percent(page.sum(resource) , pages.first.sum(resource))
      when "avg"
        div_percent(page.avg(resource) , pages.first.avg(resource))
      when "count"
        div_percent(page.count, pages.first.count)
      when "stddev"
        div_percent(page.stddev(resource), pages.first.stddev(resource))
      else
        logger.error ArgumentError.new("unknown grouping function: '#{gf}'")
        0.0
      end
    end

    def div_percent(a, b)
      b == 0 ? 0 : (a.to_f / b) * 100
    end

    def triangle_right
      '<span class="triangle">▶</span>'.html_safe
    end

    SEVERITY_LABELS = %w(DEBUG INFO WARN ERROR FATAL)

    def format_severity(severity)
      severity.is_a?(String) ? severity : (severity && SEVERITY_LABELS[severity]) || "UNKNOWN"
    end

    def severity_icon(severity, params = {})
      img = format_severity(severity).downcase
      image_tag("#{img}.svg", params.reverse_merge(:class => "lj-ico", :title => "log severity: #{img}"))
    end

    def extract_error(log_lines, exception)
      regex = Regexp.new(Regexp.escape exception.to_s) unless exception.blank?
      error_line = ''
      error_level = 0
      log_lines.each do |s,t,l|
        s = virtual_log_level(l, s)
        next unless s >= 2
        next if s <= error_level
        error_level = s
        error_line = l.to_s
        break if exception && error_line =~ regex
      end
      safe_h(error_line[0..100])
    end

    def format_log_level(l)
      severity_icon(l)
    end

    def cleanup_line(l)
      l.gsub(/\e\[[\d;]*m/, '') rescue l
    end

    def format_timestamp(timestamp)
      t = timestamp[/\d\d:\d\d:\d\d(\.\d*)?/]
      "<span class='timestamp'>#{t}</span>"
    end

    def format_backtrace(l)
      if l.include?("\n") && l !~ /\[\S+?\.pm:\d+\] &lt;/
        bt = l
      else
        bt = l.gsub(/(\s+\S+?\.rb:\d+:in \`.*?\')/){|x| "\n" << x}
        bt.gsub!(/(&lt; \S+? \[\S+?\.pm:\d+\])/){|x| "\n" << x}
        bt.sub!(/(\(\S+? \[\S+?\.pm:\d+\])/){|x| "\n" << x}
        bt.gsub!(/(\n\n)/, "\n")
      end
      "<span class='error'>#{cleanup_line(bt)}</span>"
    end

    def format_log_line(line)
      if line.is_a?(String)
        level = 1
      elsif line.size == 2
        level, line = line
      else
        level, timestamp, line = line
      end
      l = (safe_h line).strip
      vlevel = virtual_log_level(l, level)
      if l =~ /X-Logjam-Request-Id: ([-\w]+)/i
        request_id = $1
        l.sub!(request_id, sometimes_link_to_request(request_id))
      end
      colored_line = vlevel > 1 ? format_backtrace(l) : cleanup_line(l)
      "#{format_log_level(level)} #{format_timestamp(timestamp.to_s)} <span class='lb'>#{colored_line}</span>"
    end

    def has_backtrace(line)
      line =~ /\.rb:\d+:in/
    end

    def has_logged_error(line)
      line =~ /Error|Exception/
    end

    def standard_rails_line(line)
      line =~ /^(Rendering|Completed|Processing|Parameters)/
    end

    def virtual_log_level(line, level)
      if level < 2 && (has_backtrace(line) || has_logged_error(line)) && !standard_rails_line(line)
        2
      else
        level
      end
    end

    def line_times(lines)
      return [] if lines.empty?
      last, *rest = lines.map{|l| Time.parse(l[1])}
      relative_times = [0]
      while current = rest.shift
        relative_times << current - last
        last = current
      end
      if (max = relative_times.max) == 0
        relative_times
      else
        factor = 1.0 / max
        relative_times.map{|t| t * factor}
      end
    rescue
      lines.map{0}
    end

    def apdex_bounds
      if @section == :frontend
        {:happy => 0.5, :satisfied => 2, :tolerating => 8}
      else
        {:happy => 0.1, :satisfied => 0.5, :tolerating => 2}
      end
    end

    # human resource name (escaped)
    def hrn(s)
      s.gsub(/_/, ' ').gsub('∙','.')
    end

    def page_type
      if @dataset.namespace?
        "namespace"
      elsif @dataset.action?
        "action"
      else
        "actions matching"
      end
    end

    # human page name (for, of)
    def hpn(prefix)
      if @dataset.top_level?
        ""
      else
        "#{prefix} #{page_type} «#{@page.sub(/\A::/,'')}»"
      end
    end

    def format_hash(hash)
      contents = hash.keys.sort.map do |k|
        val = hash[k]
        if k =~ /\ACOOKIE\z/i
          val = val.split(/\s*;\s*/).compact.sort.map{|s| h s}.join("</br>")
        else
          val = h(val)
        end
        "<tr><td class='resource_name'>#{h k}</td><td>#{val}</td></tr>"
      end.join("\n")
      "<table class='embedded_table'>#{contents}</table>"
    end

    # try to fix broken string encodings. most of the time the string is latin-1 encoded
    def safe_h(s)
      h(s)
    rescue ArgumentError
      raise unless $!.to_s == "invalid byte sequence in UTF-8"
      logger.debug "#{$!} during html escaping".upcase
      begin
        h(s.force_encoding('ISO-8859-1').encode('UTF-8', :undef => :replace))
      rescue ArgumentError
        h(s.force_encoding('ASCII-8BIT').encode('UTF-8', :undef => :replace))
      end
    end

    def columns_for_resource(r)
      case r
      when 'total_time', 'wait_time', 'page_time', 'ajax_time' then 2
      else 3
      end
    end

    # Safari does not do proper flex box, so break it manually (arrhg)
    def order_and_slice_quants_tiles(resources)
      rc = resources.clone
      total = rc.delete('total_time') || rc.delete('page_time')
      wait = rc.delete('wait_time') || rc.delete('ajax_time')
      ordered = [total, wait].compact.concat(rc)
      # total and wait could be nil, so ...
      first = ordered.shift
      return [] if first.nil?
      second = ordered.shift
      return [[first]] if second.nil?
      # did I already mention that Safari blows?
      [[first,second]].concat(ordered.each_slice(3).to_a)
    end

    def pairs_without_trailing_zeros(data)
      res = (data||[]).reverse.drop_while{|_,d| d==0}.reverse
      res.blank? ? nil : res
    end

    def graylog_escape(s)
      s.gsub(/([:\\\/+\-!(){}\[\]^"~*?])/) do |c|
        "\\" + c
      end.gsub('&&', "\\&&").gsub('||', "\\||")
    end

    def graylog_time_range
      restricted = params[:start_minute] != FilteredDataset::DEFAULTS[:start_minute] || params[:end_minute] != FilteredDataset::DEFAULTS[:end_minute]
      if @date.nil? || (@date == Date.today && !restricted)
        { relative: 300 }
      else
        date = @date.to_time.localtime
        start_time = date + params[:start_minute].to_i.minutes
        end_time = date + params[:end_minute].to_i.minutes
        { rangetype: :absolute, from: start_time.iso8601, to: end_time.iso8601 }
      end
    end

    def graylog_uri(app, env, page = nil, options = {})
      app = graylog_escape("#{app}-#{env}")
      page = graylog_escape(page.to_s)
      fields = "source,app,message,code"
      query = "app:#{app}"
      query << " AND caller_app:unknown" if options[:unknown_callers]
      unless page.blank?
        page = '"' + page + '"' if page.include?('#')
        query << " AND message:#{page}"
      end
      uri = URI.parse(Logjam.graylog_base_urls[env.to_sym])
      uri.query = {fields: fields, q:  query}.merge(graylog_time_range).to_query
      uri.to_s
    end

    def graylog_time_range_for_given_time(started_at)
      request_time = Time.parse(started_at)
      start_time = request_time.advance(hours: -2)
      end_time = request_time.advance(hours: 2)
      { rangetype: :absolute, from: start_time.iso8601, to: end_time.iso8601 }
    end

    def graylog_trace_id_link(env, started_at, trace_id)
      fields = "source,app,message,code"
      query = "trace_id:#{trace_id}"
      graylog_uri = Logjam.graylog_base_urls[env.to_sym]
      return trace_id unless graylog_uri
      uri = URI.parse(graylog_uri)
      time_range = graylog_time_range_for_given_time(started_at)
      uri.query = {fields: fields, q:  query, }.merge(time_range).to_query
      link_to(trace_id, uri.to_s, target: "_blank")
    end

    def cached_database_storage_size
      Rails.cache.fetch("#{@app}-#{@env}-#{@date}.database_storage_size", :expires_in => 5.minutes) do
        @dataset.database_storage_size
      end
    end
  end
end

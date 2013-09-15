# -*- coding: utf-8 -*-
module Logjam

  # Methods added to this helper will be available to all templates in the application.
  module LogjamHelper
    def default_header_parameters
      FilteredDataset::DEFAULTS.merge(:time_range => 'date')
    end

    def home_url
      url_for(params.merge(:action => ''))
    end

    def history_url
      url_for(params.merge(:action => 'history'))
    end

    def self_url
      url_for(params.merge(:action => (action_name == "index" ? "" : action_name)))
    end

    def auto_complete_url_for_action_page
      url_for(params.slice(:year, :month, :day, :app, :env).merge(:action => "auto_complete_for_controller_action_page"))
    end

    def collected_time_resources
      Logjam::Resource.time_resources & @collected_resources
    end

    def collected_call_resources
      Logjam::Resource.call_resources & @collected_resources
    end

    def collected_memory_resources
      Logjam::Resource.memory_resources & @collected_resources
    end

    def collected_heap_resources
      Logjam::Resource.heap_resources & @collected_resources
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
      number_with_precision(f.to_f, :delimiter => ",", :separator => ".", :precision => 2)
    end
    alias_method :float_number, :time_number

    def memory_number(f)
      number_with_precision(f.floor, :delimiter => ",", :separator => ".", :precision => 0)
    end

    def integer_number(i)
      number_with_precision(i.to_i, :delimiter => ",", :precision => 0)
    end

    def callers_sorting_options
      %w(name count)
    end

    def callers_grouping_options
      %w(application module action)
    end

    def seconds_to_human(seconds)
      case
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

    def distribution_kind(resource)
      case Resource.resource_type(resource)
      when :time
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
      logline = line.last.strip
      tags = []
      tags << "view"      if logline =~ /^Rendered/
      tags << "api"       if logline =~ /(^API|PerlBackend)/
      tags << "memcache"  if logline =~ /^DALLI/
      tags << "rest"      if logline =~ /(^REST|RESTApi)/
      tags.join(" ")
    end

    def clean_params(params)
      FilteredDataset.clean_url_params(params.merge :default_app => @default_app, :default_env => @default_app)
    end

    def sometimes_link_grouping_result(result, grouping, params)
      value = result.send(grouping)
      ppage = params[:page]
      if grouping.to_sym == :page && ppage !~ /\AOthers/ && (ppage != @page || ppage =~ /^::/)
        params = params.merge(grouping => value)
        params[:page] = without_module(ppage) unless @page == "::"
        params[:action] = "index"
        link_to(h(value), clean_params(params), :title => "view summary")
      else
        content_tag(:span, value, :class => 'dead-link')
      end
    end

    def sometimes_link_number_of_requests(result, grouping, options)
      n = number_with_delimiter(result.count.to_i)
      if :page == grouping.to_sym && result.page != "Others..."
        link_to n, options.merge(:action => "index"), :title => "show requests"
      else
        n
      end
    end

    def sometimes_link_stddev(page, resource)
      stddev = page.stddev(resource)
      n = number_with_precision(stddev, :precision => 0 , :delimiter => ',')
      if stddev > 0 && page.page != "Others..."
        parameters = params.merge(:app => @app, :env => @env, :page => without_module(page.page), :action => distribution_kind(resource))

        link_to(n, clean_params(parameters), :title => distribution_kind(resource).to_s.gsub(/_/,' '))
      else
        n
      end
    end

    def sometimes_link_all_pages
      if params[:grouping] == "page"
        page = @page.sub(/\A::/,'')
        link_to(triangle_right,
                clean_params(params.merge(:action => "totals_overview", :page => page)),
                :title => "show all pages")
      elsif params[:grouping] == "request"
        link_to(triangle_right,
                clean_params(params.merge(:action => "request_overview", :page => @page)),
                :title => "browse requests")
      end
    end

    def link_to_request(text, options, response_code = 200)
      if response_code == 500
        link_to(text, options, :title => "show request", :class => "error")
      else
        link_to(text, options, :title => "show request")
      end
    end

    def sometimes_link_to_request(request_id)
      app, env, oid = request_id.split('-')
      if @database_info.db_exists?(@date, app, env) && Requests.exists?(@date, app, env, oid)
        parameters = params.merge(:app => app, :env => env, :action => "show", :id => oid)
        link_to(request_id, clean_params(parameters), :title => "show request")
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
        parameters = params.merge(:app => @app, :env => @env, :action => "errors", :page => without_module(page.page))
        errors = error_count == 0 ? error_count :
          link_to(integer_number(error_count), clean_params(parameters.merge(:error_type => "logged_error")), :class => "error", :title => "show errors")
        warnings = warning_count == 0 ? warning_count :
          link_to(integer_number(warning_count), clean_params(parameters.merge(:error_type => "logged_warning")), :class => "warn", :title => "show warnings")
        raw "#{errors}/#{warnings}"
      end
    end

    def sometimes_link_400s(page)
      n = page.four_hundreds
      if n == 0
        ""
      elsif page.page == "Others..."
        integer_number(n)
      else
        parameters = params.merge(:app => @app, :env => @env, :action => "response_codes", :above => 400, :page => without_module(page.page))
        link_to(integer_number(n), clean_params(parameters), :class => "warn", :title => "show 400s")
      end
    end

    def sometimes_link_response_code(page, code, n)
      text = memory_number(n)
      if code.to_i < 400
        h(text)
      else
        parameters = params.merge(:app => @app, :env => @env, :action => "response_codes", :response_code => code, :page => (@page||'::'))

        link_to(text, clean_params(parameters), :class => "error", :title => "show requests with response #{code}")
      end
    end

    def link_error_list(n, error_type, html_options={})
      page = (@page||'').gsub(/^::/,'')
      parameters = params.merge(:page => page, :action => "errors", :error_type => error_type)
      link_to(n, clean_params(parameters), html_options)
    end

    def link_exception_list(n, html_options={})
      page = (@page||'').gsub(/^::/,'')
      parameters = params.merge(:page => page, :action => "exceptions")
      link_to(n, clean_params(parameters), html_options)
    end

    def link_js_exception_list(n, html_options={})
      page = (@page||'').gsub(/^::/,'')
      parameters = params.merge(:page => page, :action => "js_exception_types")
      link_to(n, clean_params(parameters), html_options)
    end

    def without_module(page)
      page.blank? ? page : page.sub(/^::(.)/){$1}
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
        "class='active'"
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
      if Resource.resource_type(params[:resource]) == resource_type.to_sym
        "class='active' onclick=\"view_resource('#{resource}')\""
      else
        "class='inactive' onclick=\"view_resource('#{resource}')\""
      end
    end

    def triangle_right
      '<span class="triangle">▶</span>'.html_safe
    end

    SEVERITY_LABELS = %w(DEBUG INFO WARN ERROR FATAL)

    def format_severity(severity)
      severity.is_a?(String) ? severity : (severity && SEVERITY_LABELS[severity]) || "UNKNOWN"
    end

    def severity_icon(severity)
      img = format_severity(severity).downcase
      image_tag("#{img}.png", :alt => "severity: #{img}", :title => "severity: #{img}")
    end

    def extract_error(log_lines, exception)
      regex = Regexp.new(Regexp.escape exception.to_s) unless exception.blank?
      error_line = ''
      error_level = 0
      log_lines.each do |s,t,l|
        next unless s >= 2
        next if s <= error_level
        error_level = s
        error_line = safe_h(l.to_s)
        break if exception && error_line =~ regex
      end
      error_line[0..100].html_safe
    end

    def format_log_level(l)
      severity_icon(l)
    end

    def allow_breaks(l, request_id=nil)
      request_id ? l : CGI.unescape(l.gsub(/(%2C|=)/, '\1&#x200B;'))
    end

    def format_timestamp(timestamp)
      t = timestamp[/\d\d:\d\d:\d\d(\.\d*)?/]
      "<span class='timestamp'>#{t}</span>"
    end

    def format_backtrace(l, request_id=nil)
      if l.include?("\n") && l !~ /\[\S+?\.pm:\d+\] &lt;/
        bt = l
      else
        bt = l.gsub(/(\s+\S+?\.rb:\d+:in \`.*?\')/){|x| "\n" << x}
        bt.gsub!(/(&lt; \S+? \[\S+?\.pm:\d+\])/){|x| "\n" << x}
        bt.sub!(/(\(\S+? \[\S+?\.pm:\d+\])/){|x| "\n" << x}
        bt.gsub!(/(\n\n)/, "\n")
      end
      "<span class='error'>#{allow_breaks(bt, request_id)}</span>"
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
      has_backtrace = l =~ /\.rb:\d+:in/
      level = 2 if level == 1 && (has_backtrace || l =~ /Error|Exception/) && (l !~ /^(Rendering|Completed|Processing|Parameters)/)
      if l =~ /X-Logjam-Request-Id: (\S+)/
        request_id = $1
        l.sub!(request_id, sometimes_link_to_request(request_id))
      end
      colored_line = level > 1 ? format_backtrace(l, request_id) : allow_breaks(l, request_id)
      "#{format_log_level(level)} #{format_timestamp(timestamp.to_s)} #{colored_line}"
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

    # human resource name (escaped)
    def hrn(s)
      s.gsub(/_/, ' ').gsub('∙','.')
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
  end
end

module Logjam

  # Methods added to this helper will be available to all templates in the application.
  module LogjamHelper
    def time_number(f)
      number_with_precision(f.to_f, :delimiter => ",", :separator => ".", :precision => 2)
    end

    def memory_number(f)
      number_with_precision(f.floor, :delimiter => ",", :separator => ".", :precision => 0)
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

    def clean_params(params)
      FilteredDataset.clean_url_params params
    end

    def sometimes_link_grouping_result(result, grouping, params)
      value = result.send(grouping)
      ppage = params[:page]
      if grouping.to_sym == :page && ppage !~ /Others/ && (ppage != @page || ppage =~ /^::/)
        params = params.merge(grouping => value)
        params[:page] = without_module(ppage) unless @page == "::"
        link_to(h(value), clean_params(params), :title => "filter with #{h(value)}")
      else
        content_tag(:span, value, :class => 'dead-link')
      end
    end

    def sometimes_link_number_of_requests(result, grouping, options)
      n = number_with_delimiter(result.count.to_i)
      if :page == grouping.to_sym && result.page != "Others..."
        link_to n, options, :title => "show requests"
      else
        n
      end
    end

    def sometimes_link_stddev(page, resource)
      stddev = page.stddev(resource)
      n = number_with_precision(stddev, :precision => 0 , :delimiter => ',')
      if stddev > 0 && page.page != "Others..."
        parameters = params.merge(:app => @app, :env => @env, :page => without_module(page.page), :action => distribution_kind(resource))

        link_to(n, clean_params(parameters), :title => distribution_kind(resource).to_s.gsub(/_/,''))
      else
        n
      end
    end

    def link_to_request(text, options, response_code)
      if response_code == 500
        link_to(text, options, :title => "show request", :class => "error")
      else
        link_to(text, options, :title => "show request")
      end
    end

    def sometimes_link_errors(page, n)
      if n == 0
        ""
      elsif page == "Others..."
        n
      else
        parameters = params.slice(:year,:month,:day).
          merge(:app => @app, :env => @env, :action => "errors", :error_type => "logged_error", :page => without_module(page))

        link_to(n, clean_params(parameters), :class => "error")
      end
    end

    def sometimes_link_errors(page)
      error_count = page.error_count
      warning_count = page.warning_count
      n = error_count + warning_count
      if n == 0
        ""
      elsif page.page == "Others..."
        "#{error_count}/#{warning_count}"
      else
        parameters = params.slice(:year,:month,:day).
          merge(:app => @app, :env => @env, :action => "errors", :page => without_module(page.page))
        errors = error_count == 0 ? error_count :
          link_to(error_count, clean_params(parameters.merge(:error_type => "logged_error")), :class => "error")
        warnings = warning_count == 0 ? warning_count :
          link_to(warning_count, clean_params(parameters.merge(:error_type => "logged_warning")), :class => "warn")
        "#{errors}/#{warnings}"
      end
    end

    def sometimes_link_response_code(page, code, n)
      text = memory_number(n)
      if code.to_i < 400
        h(text)
      else
        parameters = params.slice(:year,:month,:day).
          merge(:app => @app, :env => @env, :action => "response_codes", :response_code => code, :page => (@page||'').gsub(/^::/,''))

        link_to(text, clean_params(parameters), :class => "error")
      end
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

    def html_attributes_for_resource_type(resource_type)
      resource = Resource.default_resource(resource_type)
      if Resource.resource_type(params[:resource]) == resource_type.to_sym
        "class='active' title='analyzing #{resource_type} resources' onclick=\"view_resource('#{resource}')\""
      else
        "class='inactive' title='analyze #{resource_type} resources' onclick=\"view_resource('#{resource}')\""
      end
    end

    SEVERITY_LABELS = %w(DEBUG INFO WARN ERROR FATAL)

    def format_severity(severity)
      severity.is_a?(String) ? severity : (severity && SEVERITY_LABELS[severity]) || "UNKNOWN"
    end

    def severity_icon(severity)
      img = format_severity(severity).downcase
      image_tag("#{img}.png", :alt => "severity: #{img}", :title => "severity: #{img}")
    end

    def extract_exception(log_lines)
      log_lines.map{|l| safe_h(l)}.detect{|l| l =~ /rb:\d+:in|Error|Exception/}.to_s[0..70]
    end

    def extract_error(log_lines)
      return extract_exception(log_lines) if log_lines.first.is_a?(String) || log_lines.blank?
      if log_lines.first.size == 2
        safe_h((log_lines.detect{|(s,l)| s >= 3}||[])[1].to_s)[0..70]
      else
        safe_h((log_lines.detect{|(s,t,l)| s >= 3}||[])[2].to_s)[0..70]
      end
    end

    def format_log_level(l)
#      "&#10145;"
      severity_icon(l)
    end

    def allow_breaks(l)
      CGI.unescape(l.gsub(/(%2C|=)/, '\1&#x200B;'))
    end

    def format_log_line(line)
      if line.is_a?(String)
        level = 1
      elsif line.size == 2
        level, line = line
      else
        level, timestamp, line = line
      end
      l = safe_h line
      has_backtrace = l =~ /\.rb:\d+:in/
      level = 2 if level == 1 && (has_backtrace || l =~ /Error|Exception/) && (l !~ /^(Rendering|Completed|Processing|Parameters)/)
      colored_line = level > 1 ? "<span class='error'>#{allow_breaks(l.gsub(/(\s+\S+?\.rb:\d+:in \`.*?\')/){|x| "\n"<<x})}</span>" : allow_breaks(l)
      "#{format_log_level(level)}<span class='timestamp'>#{timestamp.to_s[6..-1]}</span> #{colored_line}"
    end

    # human resource name (escaped)
    def hrn(s)
      h(s.gsub(/_/, ' '))
    end

    # try to fix broken string encodings. most of the time the string is latin-1 encoded
    if RUBY_VERSION >= "1.9"
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
    else
      def safe_h(s)
        h(s)
      end
    end
  end
end

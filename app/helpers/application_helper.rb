# Methods added to this helper will be available to all templates in the application.
module ApplicationHelper
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

  def sometimes_link_grouping_result(result, grouping)
    value = result[grouping]
    if [:user_id, :page].include? grouping.to_sym
      link_to(h(value), {:params => params.merge(grouping => value)}, :title => "filter with #{h(value)}")
    else
      h(value)
    end
  end

  def sometimes_link_number_of_requests(result, grouping, options)
    if :page == grouping.to_sym
      link_to number_with_delimiter(result[:number_of_requests].to_i), options, :title => "plot request time distribution for #{result[:page]}"
    else
      h(result[:number_of_requests])
    end
  end

  def sometimes_link_errors(page, n)
    if n == 0
      ""
    else
      link_to(n, :params => params.slice(:year,:month,:day).merge(:action => "errors", :page => page))
    end
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

class FilteredDataset
  HEAP_SLOT_SIZE = 40

  attr_accessor :klazz, :interval, :user_id, :host, :page, :response_code,
                :plot_kind, :heap_growth_only, :resource, :grouping, :grouping_function,
                :start_hour, :end_hour

  DEFAULTS = {:plot_kind => :time, :interval => '5',
              :grouping => 'page', :resource => 'total_time', :grouping_function => 'sum',
              :start_hour => '0', :end_hour => '24'}

  def self.is_default?(attribute, value)
    DEFAULTS.keys.include?(attribute) && DEFAULTS[attribute.to_sym].to_s == value
  end

  def initialize(options = {})
    most_recent_date_with_data = ControllerAction.log_data_dates.first
    @klazz = options[:class] || ControllerAction.class_for_date(most_recent_date_with_data)
    @interval = (options[:interval] || DEFAULTS[:interval]).to_i
    @user_id = options[:user_id] if options[:user_id].present?
    @host = options[:host] if options[:host].present?
    @page = options[:page] if options[:page].present?
    @response_code = options[:response_code] if options[:response_code].present?
    @heap_growth_only = options[:heap_growth_only].present?
    @plot_kind = options[:plot_kind] || DEFAULTS[:plot_kind]
    @resource = options[:resource] || DEFAULTS[:resource]
    @grouping = options[:grouping]
    @grouping_function = options[:grouping_function] || DEFAULTS[:grouping_function]
    @start_hour = (options[:start_hour] || DEFAULTS[:start_hour]).to_i
    @end_hour = (options[:end_hour] || DEFAULTS[:end_hour]).to_i
  end

  def stripped_page
    @page.blank? ? "" : @page.gsub(/%/,'')
  end

  def description
    Resource.description(resource, grouping, grouping_function)
  end

  def grouping?
    Resource.grouping?(grouping)
  end

  def starts_at
    @klazz.date + start_hour.hours
  end

  def ends_at
    @klazz.date + end_hour.hours
  end

  def hash
    Digest::MD5.hexdigest "#{@klazz.date} #{interval} #{user_id} #{host} #{page} #{response_code} #{plot_kind} #{start_hour} #{end_hour}"
  end

  def svg_file
    "plot-#{hash}.svg"
  end

  def png_file
    "plot-#{hash}.png"
  end

  def path(file)
    "public/images/#{file}"
  end

  def accumulates_time?
    (Resource.resource_type(resource) == :time) && grouping? && grouping_function.to_sym == :sum
  end

  def start_interval
    start_hour * intervals_per_hour
  end

  def end_interval
    end_hour * intervals_per_hour
  end

  def intervals_per_day
    24 * 60 / interval
  end

  def intervals_per_hour
    60 / interval
  end

  def empty?
    # count_requests == 0
    count_requests == 0
  end

  def count_requests(extra_condition = nil)
    @count_requests ||= {}
    # @count_requests[extra_condition] ||= @klazz.connection.select_value("select count(id) from #{@klazz.table_name} #{sql_conditions(extra_condition)}").to_i
    totals(stripped_page).count
  end

  def count_distinct_users
    @count_distinct_users ||= @klazz.connection.select_value("select count(distinct user_id) from #{@klazz.table_name} #{sql_conditions}").to_i
  end

  def count
    totals("all_pages").count
  end

  def sum(time_attr = 'total_time')
    # @sum[time_attr] ||= @klazz.connection.select_value("select sum(#{time_attr}) from #{@klazz.table_name} #{sql_conditions}").to_f
    totals(stripped_page).sum(time_attr)
  end

  def sql_conditions(extra_condition = nil)
    result = []
    result << "(user_id = #{user_id})" if user_id
    result << "(host = '#{host}')" if host
    unless page.blank?
      if page =~ /%/
        result << "(page LIKE '#{page}')"
      else
        result << "(page = '#{page}')"
      end
    end
    unless start_hour == 0 && end_hour == 24
      result << "minute5 BETWEEN #{60/5 * start_hour} AND #{(60/5 * end_hour) - 1}"
    end
    result << "(response_code = #{response_code})" if response_code
    result << "(heap_growth > 0)" if heap_growth_only
    result << "(#{extra_condition})" if extra_condition

    result.empty? ? '' : "WHERE #{result.join(' AND ')}"
  end

  def the_query
    selects = []
    if grouping?
      selects << grouping if grouping?
      selects << 'count(id) AS number_of_requests'
      if resource == 'requests'
        order = 'number_of_requests'
      else
        selects << "#{grouping_function}(#{resource}) AS #{grouping_function}"
        selects << "avg(#{resource}) AS avg" unless grouping_function == :avg
        selects << "stddev_pop(#{resource}) AS stddev"
        order = grouping_function
      end
      direction = grouping_function == :min ? 'ASC' : 'DESC'
    else
      selects << 'user_id'
      selects << 'page'
      if resource != 'requests'
        selects << resource
        order = resource
      end
      direction = 'DESC'
    end
    %Q|SELECT #{selects.join(', ')} FROM #{@klazz.table_name} #{sql_conditions} #{"GROUP BY #{grouping}" if grouping?} #{"ORDER BY #{order} #{direction}" if order} LIMIT 25|
  end

  def do_the_query
    # result = @klazz.find_by_sql the_query
    # puts result.inspect
    if resource == "requests"
      sort_by = "number_of_requests"
    else
      sort_by = "#{resource}_#{grouping_function}"
    end
    totals(stripped_page).pages(:order => sort_by, :limit => 35)
  end

  def totals(stripped_page)
    (@totals||={})[stripped_page] ||=
      case Resource.resource_type(resource)
      when :time   then Totals.new(Resource.time_resources, stripped_page)
      when :call   then Totals.new(Resource.call_resources, stripped_page)
      when :memory then Totals.new(Resource.memory_resources, stripped_page)
      end
  end

  def sql_for_time_attributes(attributes, func, prefix = '')
    attributes.map{|type| "#{func}(#{type}) as #{prefix}#{type}"}.join(', ')
  end

  def sql_for_call_attributes(attributes, func, prefix = '')
    attributes.uniq.map do |type|
      if type == "requests"
        "count(1)/#{interval} as requests"
      else
        "#{func}(#{type}) as #{prefix}#{type}"
      end
    end.join(', ')
  end

  def measures_bytes?(attr)
    [:allocated_memory, :allocated_bytes].include? attr.to_sym
  end

  def sql_for_memory_attributes(attributes, func, prefix = '')
    attributes.map{|type| "#{func}(#{!measures_bytes?(type.to_sym) ? "40 * #{type}" : type}) as #{prefix}#{type}"}.join(', ')
  end

  def statistics(resource_type)
    @statistics ||=
      begin
        resources = Resource.resources_for_type(resource_type)
        # averages = send("sql_for_#{resource_type}_attributes", resources, :avg, 'avg_')
        # stddevs = send("sql_for_#{resource_type}_attributes", resources, :stddev_pop, 'std_')
        # @klazz.connection.select_one("SELECT #{averages}, #{stddevs} FROM #{@klazz.table_name} #{sql_conditions}")
        stats = {}
        resources.each do |r|
          stats["avg_#{r}"] = totals(stripped_page).avg(r)
          stats["std_#{r}"] = totals(stripped_page).stddev(r)
        end
        stats
      end
  end

  def plot_data(resource_type, resources_to_skip = [], func = :avg)
    @plot_data ||=
      begin
        # func = grouping_function.to_sym if @resource == "requests" && resource_type.to_sym == :call
        resources = Resource.resources_for_type(resource_type) - resources_to_skip
        # attributes = send("sql_for_#{resource_type}_attributes", resources, func)
        # results = []
        minute = "minute#{interval}"
        # query = "SELECT #{minute}, #{attributes} FROM #{@klazz.table_name} #{sql_conditions} GROUP BY 1"
        # puts query
        # from_db = @klazz.connection.select_all query
        from_db = Minutes.new(resources, stripped_page).minutes
        zero = Hash.new(0)
        results = (1..intervals_per_day).to_a.map{zero}
        from_db.each {|row| results[row[minute].to_i] = row}
        # puts "RESULTS"
        # puts results.inspect
        results
      end
  end

  def get_data_for_distribution_plot(what_to_plot)
    case what_to_plot
    when :request_time
      attrs = Resource.time_resources
      quants = lambda {|a| "ceil(((#{a}-5)*sign(#{a}-5)/10))*10" }
      kind = "t"
    when :allocated_objects
      attrs = %w(allocated_objects)
      quants = lambda {|a| "ceil(((#{a}-50)*sign(#{a}-50)/100))*100" }
      kind = "m"
    when :allocated_bytes
      attrs = %w(allocated_bytes)
      quants = lambda {|a| "ceil(((#{a}-500)*sign(#{a}-500)/1000))*1000" }
      kind = "m"
    end
    the_quants = Quants.new(stripped_page, kind, attrs)
    attrs.each do |a|
      # avg_and_std_dev = @klazz.connection.select_all "select avg(#{a}) as avg, stddev_pop(#{a}) as stddev from #{@klazz.table_name} #{sql_conditions}"
      instance_variable_set "@#{a}_avg", totals(stripped_page).avg(a)
      instance_variable_set "@#{a}_stddev", totals(stripped_page).stddev(a)
      # quants_for_attr = @klazz.connection.select_all "select #{quants.call(a)} as quant, count(*) as count from #{@klazz.table_name} #{sql_conditions} group by 1"
      instance_variable_set "@#{a}_quants", the_quants.quants(a)
    end
  end

  # probably trying too hard to do something sensible when the number of requests is small.
  # this approach biases things in the direction of making everything look a bit slower/fatter,
  # by giving the extra requests to the lower bins.
  def limit_and_offset(n)
    fifth = count_requests / 5
    remainder = count_requests % 5
    limit = fifth + (n <= remainder ? 1 : 0)
    offset = (n-1) * fifth + (n <= remainder ? n-1 : remainder)
    [limit, offset]
  end

  def average_total_time_by_quintile(n)
    limit, offset = limit_and_offset(n)
    @klazz.connection.select_value("SELECT avg(total_time) FROM (SELECT total_time FROM #{@klazz.table_name} #{sql_conditions} ORDER BY total_time LIMIT #{limit} OFFSET #{offset}) AS log") || 0
  end

  def average_total_memory_by_quintile(n)
    limit, offset = limit_and_offset(n)
    @klazz.connection.select_value("SELECT avg(allocated_memory) FROM (SELECT allocated_memory FROM #{@klazz.table_name} #{sql_conditions} ORDER BY allocated_memory LIMIT #{limit} OFFSET #{offset}) AS log") || 0
  end

  def satisfaction
    @satisfaction ||= Totals.new(%w(apdex), stripped_page)
  end

  def happy
    satisfaction.apdex["happy"].to_f / satisfaction.count.to_f
  end

  def satisfied
    satisfaction.apdex["satisfied"].to_f / satisfaction.count.to_f
  end

  def tolerating
    satisfaction.apdex["tolerating"].to_f / satisfaction.count.to_f
  end

  def frustrated
    satisfaction.apdex["frustrated"].to_f / satisfaction.count.to_f
  end

  def apdex
    satisfied + tolerating / 2.0
  end

  def response_codes
    @response_codes ||= Totals.new(%w(response), stripped_page).response_codes
  end
end

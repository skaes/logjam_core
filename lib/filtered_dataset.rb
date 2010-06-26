class FilteredDataset
  HEAP_SLOT_SIZE = 40

  attr_accessor :interval, :user_id, :host, :page, :response_code,
                :plot_kind, :heap_growth_only, :resource, :grouping, :grouping_function,
                :start_hour, :end_hour, :date

  DEFAULTS = {:plot_kind => :time, :interval => '5',
              :grouping => 'page', :resource => 'total_time', :grouping_function => 'sum',
              :start_hour => '0', :end_hour => '24'}

  def self.is_default?(attribute, value)
    DEFAULTS.keys.include?(attribute) && DEFAULTS[attribute.to_sym].to_s == value
  end

  def initialize(options = {})
    @date = options[:date]
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

  def hash
    Digest::MD5.hexdigest "#{date} #{interval} #{user_id} #{host} #{page} #{response_code} #{plot_kind} #{start_hour} #{end_hour}"
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
    (Resource.resource_type(resource) == :time) && grouping? && [:sum, :avg, :stddev].include?(grouping_function.to_sym)
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
    count_requests == 0
  end

  def count_requests(extra_condition = nil)
    totals(stripped_page).count
  end

  def count
    totals("all_pages").count
  end

  def sum(time_attr = 'total_time')
    totals(stripped_page).sum(time_attr)
  end

  def do_the_query
    if grouping == "request"
      Requests.new(@date, resource, stripped_page, :heap_growth_only => heap_growth_only).all
    else
      if resource == "requests"
        sort_by = "number_of_requests"
      else
        sort_by = "#{resource}_#{grouping_function}"
      end
      totals(stripped_page).pages(:order => sort_by, :limit => 35)
    end
  end

  def totals(stripped_page)
    (@totals||={})[stripped_page] ||=
      case Resource.resource_type(resource)
      when :time   then Totals.new(@date, Resource.time_resources+%w(apdex), stripped_page)
      when :call   then Totals.new(@date, Resource.call_resources, stripped_page)
      when :memory then Totals.new(@date, Resource.memory_resources, stripped_page)
      end
  end


  def measures_bytes?(attr)
    [:allocated_memory, :allocated_bytes].include? attr.to_sym
  end

  def statistics(resource_type)
    @statistics ||=
      begin
        resources = Resource.resources_for_type(resource_type)
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
        resources = Resource.resources_for_type(resource_type) - resources_to_skip
        minute = "minute#{interval}"
        from_db = Minutes.new(@date, resources, stripped_page).minutes
        zero = Hash.new(0)
        results = (1..intervals_per_day).to_a.map{zero}
        from_db.each {|row| results[row[minute].to_i] = row}
        results
      end
  end

  def get_data_for_distribution_plot(what_to_plot)
    case what_to_plot
    when :request_time
      attrs = Resource.time_resources
      kind = "t"
    when :allocated_objects
      attrs = %w(allocated_objects)
      kind = "m"
    when :allocated_bytes
      attrs = %w(allocated_bytes)
      kind = "m"
    end
    the_quants = Quants.new(@date, stripped_page, kind, attrs)
    attrs.each do |a|
      instance_variable_set "@#{a}_avg", totals(stripped_page).avg(a)
      instance_variable_set "@#{a}_stddev", totals(stripped_page).stddev(a)
      instance_variable_set "@#{a}_quants", the_quants.quants(a)
    end
  end

  def satisfaction
    @satisfaction ||= Totals.new(@date, %w(apdex), stripped_page)
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
    @response_codes ||= Totals.new(@date, %w(response), stripped_page).response_codes
  end
end

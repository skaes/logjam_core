require 'yaml'

class Resource
  class << self

    def resources_for_type(type)
      case type
        when :time then Resource.time_resources
        when :memory then Resource.memory_resources
        else
          Resource.call_resources
        end
    end

    def resource_map
      @resource_map ||= begin
        hash = YAML.load_file(RAILS_ROOT + '/config/logjam.yml')
        hash.merge(hash){|k, v| v||[]} # convert nils to []
      end
    end

    def time_resources
      resource_map["time_resources"].map{|r| r.keys}.flatten
    end

    def memory_resources
      resource_map["memory_resources"].map{|r| r.keys}.flatten
    end

    def call_resources
      resource_map["call_resources"].map{|r| r.keys}.flatten
    end

    # returns a Hash mapping resources to colors, used for plotting
    def colors
      Hash[*resource_map.values.flatten.map {|h| [h.keys.first, h.values.first]}.flatten]
    end

    def resource_name(resource)
      resource.to_s.gsub('_', ' ')
    end

    def resource_options
      ((memory_resources.empty? ? [] : memory_resources + [nil]) + call_resources + [nil] + time_resources).map {|r| [resource_name(r), r]}
    end

    def resource_type(resource)
      if time_resources.include? resource
        :time
      elsif call_resources.include? resource
        :call
      elsif memory_resources.include? resource
        :memory
      else
        nil
      end
    end

    def groupings
      result = ['response_code']
      result += ['host']
      result += ['session_id'] if ControllerAction.column_names.include? 'session_id'
      result += ['page']
      result += ['user_id'] if ControllerAction.column_names.include? 'user_id'
      result += ['minute1']
      result += ['request']
      result
    end

    def humanname_for_grouping
      {:response_code => 'response codes', 
       :host => 'servers',
       :session_id => 'sessions',
       :page => 'pages',
       :user_id => 'users',
       :minute1 => 'minutes',
       :request => 'requests'}
    end

    def grouping_options
      groupings.map{|grouping| [humanname_for_grouping[grouping.to_sym], grouping]}
    end

    def grouping_functions
      ['sum', 'avg', 'min', 'max']
    end
    
    def grouping?(grouping)
      grouping.to_sym != :request
    end

    def description(resource, grouping, grouping_function)
      name = resource_name(resource).sub('sql query ', '')
      type = resource_type(resource)
      human_grouping = humanname_for_grouping[grouping.to_sym]
      worst = {:time => 'slowest', :call => 'busiest', :memory => 'piggiest'}[type]
      # most = {:time => 'slowest', :call => 'most', :memory => 'largest'}[type]
      # fewest = {:time => 'fastest', :call => 'fewest', :memory => 'smallest'}[type]
      # using = {:time => 'using', :call => 'making', :memory => 'using'}[type]
      # least = {:time => 'least', :call => 'fewest', :memory => 'least'}[type]
      # best = {:time => 'fastest', :call => 'least busy', :memory => 'skinniest'}[type]

      if grouping?(grouping)
        case grouping_function.to_sym
        when :sum
          "#{worst} #{human_grouping} by overall #{name}"
        when :avg
          "#{worst} #{human_grouping} by average #{name}"
        when :min
          "#{human_grouping} with requests with min #{name}"
        when :max
          "#{human_grouping} with requests with max #{name}"
        end
      else
        "#{human_grouping} with the most #{name}"
      end
    end

  end
end

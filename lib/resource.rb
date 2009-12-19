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
      resource_map["call_resources"].map{|r| r.keys}.flatten + ['1'] # for requests
    end

    # returns a Hash mapping resources to colors, used for plotting
    def colors
      Hash[*resource_map.values.flatten.map {|h| [h.keys.first, h.values.first]}.flatten]
    end

    def resource_name(resource)
      case resource
      when '1'
        'requests'
      when nil
        ''
      else
        resource.to_s.gsub('_', ' ')
      end
    end

    def resource_options
      (memory_resources + [nil] + call_resources + [nil] + time_resources).map {|r| [resource_name(r), r]}
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
        ['response_code', 'host', 'session_id', 'page', 'user_id', 'minute1', 'request']
    end

    def grouping_functions
      ['', 'min', 'max', 'avg', 'sum']
    end
    
    def grouping?(grouping)
      grouping != 'request'
    end

    def description(resource, grouping, grouping_function)
      name = resource_name(resource)
      type = resource_type(resource)
      using = {:time => 'consuming', :call => 'making', :memory => 'using'}[type]
      worst = {:time => 'slowest', :call => 'busiest', :memory => 'piggiest'}[type]
      fewest = {:time => 'fastest', :call => 'fewest', :memory => 'smallest'}[type]
      most = {:time => 'slowest', :call => 'most', :memory => 'largest'}[type]

      if grouping?(grouping)
        case grouping_function
        when :sum
          "#{grouping}s #{using} the most total #{name}"
        when :avg
          "#{worst} #{grouping}s by #{name}"
        when :min
          "#{grouping}s with the #{fewest} #{name}"
        when :max
          "#{grouping}s with the #{most} #{name}"
        end
      else
        "#{grouping}s #{using} the most #{name}"
      end
    end

  end
end

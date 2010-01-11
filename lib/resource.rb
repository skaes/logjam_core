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
      result = ['response_code', 'host'] 
      result += ['session_id'] if ControllerAction.column_names.include? 'session_id'
      result += ['page']
      result += ['user_id'] if ControllerAction.column_names.include? 'user_id'
      result += ['minute1', 'request']
      result
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
      fewest = {:time => 'fastest', :call => 'fewest', :memory => 'smallest'}[type]
      most = {:time => 'slowest', :call => 'most', :memory => 'largest'}[type]

      if grouping?(grouping)
        case grouping_function
        when :sum
          "#{grouping}s #{using} the most #{name}"
        when :avg
          "#{grouping}s #{using} the most (on average) #{name}"
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

require 'yaml'
module Logjam

  class Resource
    class << self

      def resources_for_type(type)
        case type
        when :time   then Resource.time_resources
        when :memory then Resource.memory_resources
        when :call   then Resource.call_resources
        end
      end

      def resource_map
        @resource_map ||=
          begin
            hash = YAML.load_file(RAILS_ROOT + '/config/logjam_resources.yml')
            hash.merge(hash){|k, v| v||[]} # convert nils to []
          end
      end

      def all_resources
        @all_resources ||= resource_map.values.flatten.map(&:keys).flatten
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

      def heap_resources
        resource_map["heap_resources"].map{|r| r.keys}.flatten
      end

      # returns a Hash mapping resources to colors, used for plotting
      def colors
        @colors ||= Hash[*resource_map.values.flatten.map {|h| [h.keys.first, h.values.first]}.flatten]
      end

      def color(resource, transparency=0)
        c = colors[resource]
        if transparency==0
          c
        else
          r,g,b = [c[1..2], c[3..4], c[5..6]].map{|s| s.hex}
          "rgba(#{r},#{g},#{b},#{transparency})"
        end
      end

      def colors_with_transparency(transparency)
        colors.inject({}){|h,(r,c)| h[r] = color(r,transparency); h}
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

      def resource_exists?(resource)
        all_resources.include?(resource)
      end

      def default_resource(resource_type)
        case resource_type.to_sym
        when :time   then 'total_time'
        when :call   then resource_exists?('db_calls') ? 'db_calls' : call_resources.first
        when :memory then 'allocated_objects'
        end
      end

      def groupings
        ['page', 'request']
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
        ['sum', 'avg', 'stddev', 'count']
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

        return 'nonsensical' if grouping.to_sym != :request && resource.to_sym == :heap_size && grouping_function.to_sym == :sum
        return 'nonsensical' if grouping.to_sym == :request && resource.to_sym == :requests

        if grouping?(grouping)
          case grouping_function.to_sym
          when :sum
            "#{worst} #{human_grouping} by overall #{name}"
          when :avg
            "#{worst} #{human_grouping} by average #{name}"
          when :stddev
            "#{worst} #{human_grouping} by standard deviation of #{name}"
          when :count
            "#{worst} #{human_grouping} by number of requests"
          when :min
            "#{human_grouping} with requests with min #{name}"
          when :max
            "#{human_grouping} with requests with max #{name}"
          end
        else
          "#{human_grouping} with the most #{name}"
        end
      end

      def short_description(resource, grouping, grouping_function)
        description = description(resource, grouping, grouping_function)
        description =~ /by (.*)$/ && $1
      end
    end
  end
end

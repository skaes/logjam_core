require 'yaml'
module Logjam

  class Resource
    class << self

      def resources_for_type(type)
        case type
        when :time     then Resource.time_resources
        when :memory   then Resource.memory_resources
        when :call     then Resource.call_resources
        when :heap     then Resource.heap_resources
        when :frontend then Resource.frontend_resources
        when :dom      then Resource.dom_resources
        end
      end

      def resource_map
        @resource_map ||=
          begin
            hash = YAML.load_file("#{Rails.root}/config/logjam_resources.yml")
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

      def backend_resources
        time_resources + call_resources + memory_resources + heap_resources
      end

      def frontend_resources
        resource_map["frontend_resources"].map{|r| r.keys}.flatten
      end

      def dom_resources
        resource_map["dom_resources"].map{|r| r.keys}.flatten
      end

      # returns a Hash mapping resources to colors, used for plotting
      def colors
        @colors ||=
          Hash[*resource_map.values.flatten.map {|h| [h.keys.first, h.values.first]}.flatten].merge!("free_slots"=>"#b3d1f9")
      end

      def color(resource, transparency=0)
        c = colors[resource.sub(/_max\z/,'')]
        if transparency==0
          c
        else
          r,g,b = [c[1..2], c[3..4], c[5..6]].map{|s| s.hex}
          "rgba(#{r},#{g},#{b},#{transparency})"
        end
      end

      def colors_with_transparency(transparency)
        (@colors_with_transparency ||= {})[transparency] ||= colors.keys.each_with_object({}){|r,h| h[r] = color(r, transparency) }
      end

      def resource_name(resource)
        resource.to_s.gsub('_', ' ')
      end

      def resource_options
        heap_options = heap_resources.empty? ? [] : heap_resources + [nil]
        memory_options = memory_resources.empty? ? [] : memory_resources + [nil]
        (heap_options + memory_options + call_resources + [nil] + time_resources).map {|r| [resource_name(r), r]}
      end

      def section(resource)
        if time_resources.include? resource
          :backend
        elsif call_resources.include? resource
          :backend
        elsif memory_resources.include? resource
          :backend
        elsif heap_resources.include? resource
          :backend
        elsif frontend_resources.include? resource
          :frontend
        elsif dom_resources.include? resource
          :frontend
        else
          nil
        end
      end

      def resource_type(resource)
        if time_resources.include? resource
          :time
        elsif call_resources.include? resource
          :call
        elsif memory_resources.include? resource
          :memory
        elsif heap_resources.include? resource
          :heap
        elsif frontend_resources.include? resource
          :frontend
        elsif dom_resources.include? resource
          :dom
        else
          nil
        end
      end

      def resource_exists?(resource)
        all_resources.include?(resource)
      end

      def default_resource(resource_type)
        case resource_type.to_sym
        when :time       then 'total_time'
        when :call       then resource_exists?('db_calls') ? 'db_calls' : call_resources.first
        when :memory     then 'allocated_objects'
        when :heap       then 'heap_size'
        when :frontend   then 'page_time'
        when :dom        then 'html_nodes'
        end
      end

      def groupings
        %w(page request)
      end

      def humanname_for_grouping
        {
          :response_code => 'response codes',
          :host => 'servers',
          :session_id => 'sessions',
          :page => 'actions',
          :user_id => 'users',
          :minute1 => 'minutes',
          :request => 'requests'
        }
      end

      def grouping_options
        groupings.map{|grouping| [humanname_for_grouping[grouping.to_sym], grouping]}
      end

      def grouping_functions
        %w(sum avg max stddev count apdex)
      end

      def grouping?(grouping)
        grouping.to_sym != :request
      end

      def grouping_function_description(resource, grouping_function)
        name = resource_name(resource).sub('sql query ', '')
        case grouping_function.to_sym
        when :sum
          "overall #{name}"
        when :avg
          "average #{name}"
        when :stddev
          "standard deviation of #{name}"
        when :max
          "maximum #{name}"
        when :count
          "number of requests"
        when :apdex
          "apdex score"
        end
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

        return 'nonsensical sort order' if grouping.to_sym != :request && grouping_function.to_sym == :sum &&
          [:heap_size, :live_data_set_size].include?(resource.to_sym)
        return 'nonsensical sort order' if grouping.to_sym == :request && resource.to_sym == :requests

        if grouping?(grouping)
          "#{worst} #{human_grouping} by #{grouping_function_description(resource, grouping_function)}"
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

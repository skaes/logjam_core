module Logjam

  class Requests

    GENERIC_FIELDS = %w(page host ip user_id started_at process_id minute session_id new_session response_code app env severity)

    TIME_FIELDS = Resource.time_resources

    CALL_FIELDS = Resource.call_resources

    MEMORY_FIELDS = Resource.memory_resources + Resource.heap_resources

    FIELDS = TIME_FIELDS + CALL_FIELDS + MEMORY_FIELDS

    QUANTIFIED_FIELDS = TIME_FIELDS + %w(allocated_objects allocated_bytes)

    SQUARED_FIELDS = FIELDS.inject({}) { |h, f| h[f] = "#{f}_sq"; h}

    def self.ensure_indexes(collection)
      ms = Benchmark.ms do
        (FIELDS + %w[response_code severity minute started_at]).each do |f|
          collection.create_index([ [f, Mongo::DESCENDING] ], :background => true)
          collection.create_index([ ["page", Mongo::ASCENDING], [f, Mongo::DESCENDING] ], :background => true)
        end
      end
      logger.debug "MONGO Requests Indexes Creation: #{"%.1f" % (ms)} ms"
      collection
    end

    attr_reader :resource, :pattern

    def initialize(db, resource=nil, pattern='', options={})
      @database = db
      @collection = @database["requests"]
      @resource = resource
      @pattern = pattern.to_s.sub(/^::/,'')
      @options = options
      @start_minute = @options[:start_minute] if @options[:start_minute].present? && (@options[:start_minute] != 0)
      @end_minute = @options[:end_minute] if @options[:end_minute].present? && (@options[:end_minute] != 1440)
    end

    def page_names
      @page_names ||= @database["totals"].distinct(:page)
    end

    def selector
      query_opts = @options[:heap_growth_only] ? {"heap_growth" => {'$gt' => 0}} : {}
      query_opts.merge!(:response_code => @options[:response_code]) if @options[:response_code]
      if severity = @options[:severity]
        if severity.to_i < 3
          query_opts.merge!(:severity => severity)
        else
          query_opts.merge!(:severity => {'$gte' => severity})
        end
      end
      if pattern.present? && pattern != "all_pages"
        if page_names.include?(pattern)
          query_opts.merge!(:page => pattern)
        elsif page_names.detect{|p| p =~ /^#{pattern}/}
          query_opts.merge!(:page => /^#{pattern}/)
        else
          query_opts.merge!(:page => /#{pattern}/)
        end
      end
      query_opts.merge!(:minute => {'$gte' => @start_minute}) if @start_minute
      (query_opts[:minute] ||= {}).merge!('$lte' => @end_minute) if @end_minute
      query_opts
    end

    def all
      all_fields = ["page", "user_id", "heap_growth", "response_code", "severity", @resource]
      all_fields << "minute" unless all_fields.include?("minute")
      all_fields << "lines" if @options[:response_code] == 500 ||  @options[:severity]
      query_opts = {
        :fields => all_fields,
        :sort => [@resource, Mongo::DESCENDING],
        :limit => @options[:limit] || 32,
        :skip => @options[:skip]
      }

      result = nil
      access_time = Benchmark.ms do
#         explain = @collection.find(selector, query_opts).explain
#         logger.debug explain.inspect
        result = @collection.find(selector, query_opts.dup).to_a
      end
      logger.debug "MONGO Requests(#{selector.inspect},#{query_opts.inspect}) #{result.size} records, #{"%.1f" % (access_time)} ms"
      result
    end

    def count
      @collection.find(selector).count
    end

    def find(id)
      fields = Resource
      @collection.find_one({"_id" => BSON::ObjectId.from_string(id)})
    end

    def logger
      self.class.logger
    end

    def self.logger
      Rails.logger
    end
  end

end

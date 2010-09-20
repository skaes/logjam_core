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
        collection.create_index([ ["page", Mongo::ASCENDING] ])
        collection.create_index([ ["response_code", Mongo::DESCENDING] ])
        collection.create_index([ ["severity", Mongo::DESCENDING] ])
        collection.create_index([ ["minute", Mongo::DESCENDING] ])
        collection.create_index([ ["started_at", Mongo::DESCENDING] ])
        FIELDS.each{|f| collection.create_index([ [f, Mongo::DESCENDING] ])}
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
      query_opts.merge!(:severity => {'$gte' => @options[:severity]}) if @options[:severity]
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

      result = nil
      access_time = Benchmark.ms do
        result = @collection.find(selector,
                                  {:fields => all_fields,
                                    :sort => [@resource, Mongo::DESCENDING],
                                    :limit => @options[:limit] || 32}).to_a
      end
      logger.debug "MONGO Requests(#{selector.inspect},#{all_fields.inspect}) #{result.size} records, #{"%.1f" % (access_time)} ms"
      result
    end

    def count
      @collection.find(selector).count
    end

    def find(id)
      fields = Resource
      @collection.find_one({"_id" => BSON::ObjectID.from_string(id)})
    end

    def logger
      self.class.logger
    end

    def self.logger
      Rails.logger
    end
  end

end

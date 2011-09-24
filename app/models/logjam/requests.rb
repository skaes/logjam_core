module Logjam

  class Requests

    GENERIC_FIELDS = %w(page host ip user_id started_at process_id minute session_id new_session response_code app env severity exceptions)

    TIME_FIELDS = Resource.time_resources

    CALL_FIELDS = Resource.call_resources

    MEMORY_FIELDS = Resource.memory_resources + Resource.heap_resources

    FIELDS = TIME_FIELDS + CALL_FIELDS + MEMORY_FIELDS

    QUANTIFIED_FIELDS = TIME_FIELDS + %w(allocated_objects allocated_bytes)

    SQUARED_FIELDS = FIELDS.inject({}) { |h, f| h[f] = "#{f}_sq"; h}

    INDEXED_FIELDS = FIELDS + %w[response_code severity minute exceptions]

    def self.ensure_indexes(collection)
      ms = Benchmark.ms do
        indexes_to_drop = collection.index_information.keys.select{|i| i =~ /started_at/}
        indexes_to_drop.each do |i|
          logger.info  "MONGO dropping obsolete index: #{i}"
          collection.drop_index i
        end
        INDEXED_FIELDS.each do |f|
          collection.create_index([ [f, Mongo::DESCENDING] ], :background => true, :sparse => true)
          collection.create_index([ ["page", Mongo::ASCENDING], [f, Mongo::DESCENDING] ], :background => true)
        end
      end
      logger.info "MONGO Requests Indexes Creation (#{2*INDEXED_FIELDS.size+1}): #{"%.1f" % (ms)} ms"
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
      @page_names ||=
        begin
          query = "Totals.distinct(:page)"
          ActiveSupport::Notifications.instrument("mongo.logjam", :query => query) do |payload|
            rows = @database["totals"].distinct(:page)
            payload[:rows] = rows.size
            rows
          end
        end
    end

    def selector(options={})
      query_opts = @options[:heap_growth_only] ? {"heap_growth" => {'$gt' => 0}} : {}
      if rc = @options[:response_code]
        if @options[:above]
          query_opts.merge!(:response_code => {'$gte' => rc})
        else
          query_opts.merge!(:response_code => rc)
        end
      end
      if exs = @options[:exceptions]
        query_opts.merge!(:exceptions => exs)
      end
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
      query_opts.merge!(options)
    end

    def all
      all_fields = ["page", "user_id", "heap_growth", "response_code", "severity", @resource]
      all_fields << "minute" unless all_fields.include?("minute")
      all_fields << "lines" if @options[:response_code] == 500 || @options[:severity] || @options[:exceptions]
      query_opts = {
        :fields => all_fields,
        :sort => [@resource, Mongo::DESCENDING],
        :limit => @options[:limit] || 32,
        :skip => @options[:skip]
      }

      query = "Requests.find(#{selector.inspect},#{query_opts.inspect})"
      rows = nil
      ActiveSupport::Notifications.instrument("mongo.logjam", :query => query) do |payload|
        # explain = @collection.find(selector, query_opts).explain
        # logger.debug explain.inspect
        rows = @collection.find(selector, query_opts.dup).to_a
        payload[:rows] = rows.size
      end
      rows
    end

    def count(options={})
      selector = selector(options)
      query = "Requests.count(#{selector.inspect})"
      ActiveSupport::Notifications.instrument("mongo.logjam", :query => query, :rows => 1) do
        @collection.find(selector).count
      end
    end

    def find(id)
      selector = {"_id" => BSON::ObjectId.from_string(id)}
      query = "Requests.find_one(#{selector.inspect})"
      ActiveSupport::Notifications.instrument("mongo.logjam", :query => query, :rows => 1) do
        @collection.find_one(selector)
      end
    end

    def logger
      self.class.logger
    end

    def self.logger
      Rails.logger
    end
  end

end

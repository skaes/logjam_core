module Logjam

  class Requests < MongoModel

    GENERIC_FIELDS = %w(page host ip user_id started_at process_id minute session_id new_session response_code app env severity exceptions callers)

    TIME_FIELDS = Resource.time_resources

    CALL_FIELDS = Resource.call_resources

    MEMORY_FIELDS = Resource.memory_resources + Resource.heap_resources

    FIELDS = TIME_FIELDS + CALL_FIELDS + MEMORY_FIELDS

    QUANTIFIED_FIELDS = TIME_FIELDS + %w(allocated_objects allocated_bytes)

    SQUARED_FIELDS = FIELDS.inject({}) { |h, f| h[f] = "#{f}_sq"; h}

    INDEXED_FIELDS = %w[response_code severity minute exceptions]

    def self.indexed_fields(collection)
      collection.index_information.keys.map{|i| i.gsub(/_-?1/,'')}
    end

    def self.ensure_indexes(collection)
      old_format = nil
      ms = Benchmark.ms do
        fields = indexed_fields(collection)
        old_format = fields.include?("total_time")
        if (fields & INDEXED_FIELDS) == INDEXED_FIELDS
          logger.info "MONGO assuming request indexes already exist"
        else
          logger.info "MONGO creating request indexes"
          collection.create_index([ ["metrics.n", 1], ["metrics.v", -1] ], :background => true)
          collection.create_index([ ["page", 1], ["metrics.n", 1], ["metrics.v", -1] ], :background => true)
          INDEXED_FIELDS.each do |f|
            collection.create_index([ [f, 1] ], :background => true, :sparse => true)
            collection.create_index([ ["page", 1], [f, 1] ], :background => true)
          end
        end
      end
      puts "MONGO Requests Indexes Creation (#{2*INDEXED_FIELDS.size+2+1}): #{"%.1f" % (ms)} ms"
      [collection, old_format]
    end

    def self.exists?(date, app, env, oid)
      new(Logjam.db(date, app, env)).find(oid)
    end

    attr_reader :resource, :pattern

    def initialize(db, resource=nil, pattern='', options={})
      super(db, "requests")
      @old_format = self.class.indexed_fields(@collection).include?("total_time")
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
          with_conditional_caching(query) do |payload|
            rows = @database["totals"].distinct(:page)
            payload[:rows] = rows.size
            rows
          end
        end
    end

    def selector(options={})
      if @old_format || INDEXED_FIELDS.include?(@resource)
        query_opts = {}
      else
        query_opts = {"metrics.n" => @resource}
      end
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
      fields = ["page", "user_id", "response_code", "severity"]
      if @old_format
        fields.concat ["heap_growth", @resource]
        fields << "minute" unless @resource == "minute"
      else
        fields.concat ["metrics", "minute"]
      end
      fields << "lines" if @options[:response_code] || @options[:severity] || @options[:exceptions]

      query_opts = {
        :fields => fields,
        :sort => @old_format || INDEXED_FIELDS.include?(@resource) ?  [@resource, -1] : [["metrics.n", 1], ["metrics.v", -1]],
        :limit => @options[:limit] || 25,
        :skip => @options[:skip]
      }

      query = "Requests.find(#{selector.inspect},#{query_opts.inspect})"
      rows = with_conditional_caching(query) do |payload|
        # explain = @collection.find(selector, query_opts.dup).explain
        # logger.debug explain.inspect
        rs = []
        @collection.find(selector, query_opts.dup).each do |row|
          (id = row["_id"]) && row["_id"] = id.to_s
          rs << row
          convert_metrics(row)
        end
        payload[:rows] = rs.size
        rs
      end
      rows
    end

    def count(options={})
      selector = selector(options)
      query = "Requests.count(#{selector.inspect})"
      with_conditional_caching(query) do |payload|
        payload[:rows] = 1
        @collection.find(selector).count
      end
    end

    def find(id)
      selector = {"_id" => primary_key(id)}
      query = "Requests.find_one(#{id})"
      rows = with_conditional_caching(query) do |payload|
        if row = @collection.find_one(selector)
          (id = row["_id"]) && row["_id"] = id.to_s
          convert_metrics(row)
          payload[:rows] = 1
          [row]
        else
          payload[:rows] = 0
          []
        end
      end
      rows.first
    end

    def convert_metrics(row)
      if metrics = row.delete("metrics")
        metrics.each{|m| row[m["n"]] = m["v"]}
      end
    end

    def primary_key(id)
      case id.length
      when 24
        BSON::ObjectId.from_string(id)
      when 32
        BSON::Binary.new(id, BSON::Binary::SUBTYPE_UUID)
      else
        id
      end
    end

  end

end

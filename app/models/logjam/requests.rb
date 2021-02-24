module Logjam

  class Requests < MongoModel

    GENERIC_FIELDS = %w(page host ip user_id started_at process_id minute session_id new_session response_code app env severity exceptions soft_exceptions callers)

    TIME_FIELDS = Resource.time_resources

    CALL_FIELDS = Resource.call_resources

    MEMORY_FIELDS = Resource.memory_resources + Resource.heap_resources

    FRONTEND_FIELDS = Resource.frontend_resources

    DOM_FILEDS = Resource.dom_resources

    FIELDS = TIME_FIELDS + CALL_FIELDS + MEMORY_FIELDS + FRONTEND_FIELDS + DOM_FILEDS

    QUANTIFIED_FIELDS = TIME_FIELDS + %w(allocated_objects allocated_bytes)

    SQUARED_FIELDS = FIELDS.inject({}) { |h, f| h[f] = "#{f}_sq"; h}

    INDEXED_FIELDS = %w[response_code severity exceptions]

    NON_METRIC_FIELDS = INDEXED_FIELDS + %w(minute)

    def self.indexed_fields(collection)
      collection.index_information.keys.map{|i| i.gsub(/_-?1/,'')}
    rescue Mongo::OperationFailure
      []
    end

    def self.ensure_indexes(collection, options = {})
      ms = Benchmark.ms do
        logger.info "MONGO creating request indexes"
        collection.indexes.create_one({ "metrics.n" => 1, "metrics.v" => -1 }, options)
        collection.indexes.create_one({ "page" => 1, "metrics.n" => 1, "metrics.v" => -1 }, options)
        INDEXED_FIELDS.each do |f|
          # collection.indexes.create_one({ f => 1 }, options.reverse_merge(sparse: true))
          collection.indexes.create_one({ "minute" => -1, f => 1 }, options)
          collection.indexes.drop_one("#{f}_1")
          # collection.indexes.create_one({ "page" => 1, f => 1 }, options)
          collection.indexes.create_one({ "page" => 1, "minute" => -1, f => 1 }, options)
          collection.indexes.drop_one("page_1_#{f}_1")
        end
      end
      collection.indexes.drop_one("minute_1")
      puts "MONGO requests indexes creation (#{4*INDEXED_FIELDS.size+2+1}): #{"%.1f" % (ms)} ms"
      collection
    end

    def self.exists?(date, app, env, oid)
      new(Logjam.db(date, app, env)).find(oid)
    end

    attr_reader :resource, :pattern

    def initialize(db, resource=nil, pattern='', options={})
      super(db, "requests")
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

    def modules
      @modules ||=
        begin
          modules = Set.new
          page_names.each do |page|
            modules.add $1 if page =~ /\A::([^:]+)\z/
          end
          modules
        end
    end

    def selector(options={})
      if NON_METRIC_FIELDS.include?(@resource)
        query_opts = {}
      else
        query_opts = {"metrics.n" => @resource}
      end
      if rc = @options[:response_code]
        if @options[:above]
          query_opts.merge!(:response_code => {'$gte' => rc})
          if rc < 500
            query_opts.merge!(:response_code => {'$lt' => 500})
          end
        else
          query_opts.merge!(:response_code => rc)
        end
      end
      if exs = @options[:exceptions]
        query_opts.merge!(:exceptions => exs)
      end
      if exs = @options[:soft_exceptions]
        query_opts.merge!(:soft_exceptions => exs)
      end
      if severity = @options[:severity]
        query_opts.merge!(:severity => severity)
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

    def build_metrics_query(name, selector, opts = {})
      stages = []
      stages << {'$project' => opts[:projection]}
      stages << {'$unwind' => '$metrics'}
      stages << {'$match' => selector}
      stages << {'$sort' => {'metrics.v' => -1}}
      stages << {'$skip' => opts[:skip]}
      stages << {'$limit' => opts[:limit]}
      log = "#{name}.aggregate(#{stages.to_json})"

      [@collection.find.aggregate(stages), log]
    end

    def all
      sel = selector
      fields = {
        "page" => 1, "user_id" => 1, "response_code" => 1, "severity" => 1,
        "started_at" => 1, "minute" => 1
      }
      fields["lines"] = {'$slice' => -1000} if @options[:response_code] || @options[:severity] || @options[:exceptions] || @options[:soft_exceptions]

      query_opts = {
        :projection => fields,
        :limit => @options[:limit] || 25,
        :skip => @options[:skip]
      }
      if NON_METRIC_FIELDS.include?(@resource)
        query_opts[:sort] = {@resource => -1}
        query, log = build_query("Requests.find", sel, query_opts)
      elsif collection_names.include?("metrics")
        metrics = Metrics.new(@database, self, @resource, pattern, @options).all
        threads = metrics.map{|row| Thread.new { find(row["rid"]) } }
        return threads.map{|t| t.join.value}
      elsif sel.keys == ["metrics.n"]
        # just use the index
        query_opts[:projection]["metrics"] = 1
        query, log = build_query("Requests.find", sel, query_opts)
      else
        query_opts[:projection]["metrics"] = 1
        query, log = build_metrics_query("Requests.find", sel, query_opts)
      end

      rows = with_conditional_caching(log) do |payload|
        # explain = @collection.find(selector, query_opts.dup).explain
        # logger.debug explain.inspect
        rs = []
        query.each do |row|
          if (id = row["_id"]) && id.is_a?(BSON::Binary)
            row["_id"] = id.data.to_s
          end
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
      log = "Requests.find_one(#{id})"
      rows = with_conditional_caching(log) do |payload|
        if row = @collection.find(selector).projection(:lines => {'$slice' => -1000}).limit(1).first
          if (id = row["_id"]) && id.is_a?(BSON::Binary)
            row["_id"] = id.data.to_s
          end
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
        if metrics.is_a? Hash
          row[metrics["n"]] = metrics["v"]
        else
          metrics.each {|m| row[m["n"]] = m["v"] }
        end
      end
    end

    def primary_key(id)
      if id.is_a?(BSON::ObjectId)
        id
      else
        case id.length
        when 24
          BSON::ObjectId.from_string(id)
        when 32
          BSON::Binary.new(id, :uuid_old)
        else
          id
        end
      end
    end

  end

end

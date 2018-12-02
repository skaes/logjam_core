module Logjam
  class Metrics < MongoModel

    attr_reader :pattern

    def initialize(db, requests, metric='total_time', pattern='', options={})
      super(db, "metrics")
      @metric = metric
      @options = options
      @start_minute = @options[:start_minute] if @options[:start_minute].present? && (@options[:start_minute] != 0)
      @end_minute = @options[:end_minute] if @options[:end_minute].present? && (@options[:end_minute] != 1440)
      @pattern = pattern
      @requests = requests
    end

    def count

    end

    def selector
      opts = {"metric" => @metric}
      if pattern.present? && pattern != "all_pages"
        if @requests.modules.include?(pattern.sub(/^::/,''))
          opts.merge!(:module => pattern.sub(/^::/,''))
        elsif @requests.page_names.include?(pattern)
          opts.merge!(:page => pattern)
        elsif @requests.page_names.detect{|p| p =~ /^#{pattern}/}
          opts.merge!(:page => /^#{pattern}/)
        else
          opts.merge!(:page => /#{pattern}/)
        end
      end
      opts.merge!(:minute => {'$gte' => @start_minute}) if @start_minute
      (opts[:minute] ||= {}).merge!('$lte' => @end_minute) if @end_minute
      opts
    end

    def query_options
      {:limit => 25}.merge(@options.slice(:limit, :offset, :skip)).merge(:sort => {"value" => -1})
    end

    def all
      query, log = build_query("Metrics.find", selector, query_options)
      rows = with_conditional_caching(log) do |payload|
        # explain = @collection.find(selector, query_options.dup).explain
        # logger.debug explain.inspect
        rs = []
        query.each do |row|
          if (id = row["rid"]) && id.is_a?(BSON::Binary)
            row["rid"] = id.data.to_s
          end
          rs << row
        end
        payload[:rows] = rs.size
        rs
      end
      rows
    end
  end
end

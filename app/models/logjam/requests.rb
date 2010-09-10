module Logjam

  class Requests
    attr_reader :resource, :pattern
    def initialize(db, resource=nil, pattern='', options={})
      @database = db
      @collection = @database["requests"]
      @resource = resource
      @pattern = pattern.sub(/^::/,'')
      @options = options
      @start_minute = @options[:start_minute] if @options[:start_minute].present? && (@options[:start_minute] != 0)
      @end_minute = @options[:end_minute] if @options[:end_minute].present? && (@options[:end_minute] != 1440)
    end

    def selector
      query_opts = @options[:heap_growth_only] ? {"heap_growth" => {'$gt' => 0}} : {}
      query_opts.merge!(:response_code => @options[:response_code]) if @options[:response_code]
      query_opts.merge!(:page => /#{pattern}/) unless pattern.blank? || pattern == "all_pages"
      query_opts.merge!(:minute => {'$gte' => @start_minute}) if @start_minute
      (query_opts[:minute] ||= {}).merge!('$lte' => @end_minute) if @end_minute
      query_opts
    end

    def all
      all_fields = ["page", "user_id", "heap_growth", "response_code", @resource]
      all_fields << "minute" unless all_fields.include?("minute")
      all_fields << "lines" if @options[:response_code] == 500

      result = nil
      access_time = Benchmark.ms do
        result = @collection.find(selector,
                                  {:fields => all_fields,
                                    :sort => [@resource, Mongo::DESCENDING],
                                    :limit => @options[:limit] || 35}).to_a
      end
      logger.debug "MONGO Requests(#{selector.inspect},#{all_fields.inspect}) #{result.size} records, #{"%.1f" % (access_time)} ms}"
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

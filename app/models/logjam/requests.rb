module Logjam

  class Requests
    attr_reader :resource, :pattern
    def initialize(db, resource=nil, pattern='', options={})
      @database = db
      @collection = @database["requests"]
      @resource = resource
      @pattern = pattern
      @options = options
    end

    def selector
      query_opts = @options[:heap_growth_only] ? {"heap_growth" => {'$gt' => 0}} : {}
      query_opts.merge!(:response_code => @options[:response_code]) if @options[:response_code]
      query_opts.merge!(:page => /#{pattern}/) unless pattern.blank?
      puts query_opts.inspect
      query_opts
    end

    def all
      result = []
      all_fields = ["page", "user_id", "heap_growth", "response_code", @resource]
      all_fields << "minute" unless all_fields.include?("minute")
      all_fields << "lines" if @options[:response_code] == 500
      access_time = Benchmark.realtime do
        result = @collection.find(selector,
                                  {:fields => all_fields,
                                    :sort => [@resource, Mongo::DESCENDING],
                                    :limit => @options[:limit] || 35}).to_a
      end
      logger.debug "MONGO requests #{result.size} records, #{"%.5f" % (access_time)} seconds}"
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

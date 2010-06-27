class Requests
  attr_reader :resource, :pattern
  def initialize(date, resource=nil, pattern='', options={})
    @database = Logjam.db(date)
    @collection = @database["requests"]
    @resource = resource
    @pattern = pattern
    @options = options
  end

  def selector
    query_opts = @options[:heap_growth_only] ? {"heap_growth" => {'$gt' => 0}} : {}
    query_opts.merge!(:page => /#{pattern}/) unless pattern.blank?
    puts query_opts.inspect
    query_opts
  end

  def all
    result = []
    all_fields = ["page", "user_id", "heap_growth", @resource]
    access_time = Benchmark.realtime do
      result = @collection.find(selector,
                                {:fields => all_fields,
                                  :sort => [@resource, Mongo::DESCENDING],
                                  :limit => 35}).to_a
    end
    logger.debug "MONGO requests #{result.size} records, #{"%.5f" % (access_time)} seconds}"
    result
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


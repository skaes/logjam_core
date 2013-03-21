module Logjam
  module RequestDetailPlugins
    @@request_detail_plugins = []

    def self.all
      @@request_detail_plugins
    end

    def self.add(&block)
      @@request_detail_plugins << block
    end

    def self.clear!
      @@request_detail_plugins = []
    end

    DEFAULT_REQUEST_DETAILS_PLUGIN = ->(request) do
      fields = request.keys - Logjam::Resource.time_resources -
                              Logjam::Resource.call_resources -
                              Logjam::Resource.memory_resources -
                              Logjam::Resource.heap_resources

      fields.reject!{|k| k =~ /(^_id|lines|minute|page|_sq|request_info)$/}

      locals = request.slice(*fields)

      locals["severity"]  = format_severity(request["severity"])
      locals["caller_id"] = sometimes_link_to_request(request["caller_id"])

      { :title => "Request attributes", :fields => locals }
    end

    add(&DEFAULT_REQUEST_DETAILS_PLUGIN)
  end
end
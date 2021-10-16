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
      env = request.first
      request = request.second

      fields = request.keys - ::Logjam::Resource.all_resources

      fields.reject!{|k| k =~ /(^_id|lines|minute|page|_sq|request_info)$/}

      locals = request.slice(*fields)

      if severity = request["severity"]
        locals["severity"] = format_severity(severity)
      end

      if caller_id = request["caller_id"]
        locals["caller_id"] = sometimes_link_to_request(caller_id)
      end

      if trace_id = request["trace_id"]
        locals["trace_id"] = graylog_trace_id_link(env, request["started_at"], trace_id)
      end

      { :title => "Request attributes", :fields => locals }
    end

    add(&DEFAULT_REQUEST_DETAILS_PLUGIN)
  end
end

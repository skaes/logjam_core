module Logjam
  class Importer
    def initialize
      analyze_streams
    end

    def config
      @io = StringIO.new(config = "")
      generate_frontend
      generate_backend
      generate_metrics
      generate_statsd
      config
    end

    private

    def analyze_streams
      @streams = Logjam.streams.reject do |k,s|
        s.is_a?(Logjam::LiveStream) || (s.env == "development" && Rails.env.production?)
      end
      @environments = @streams.values.map(&:env).uniq
      @endpoints = @streams.values.map{|s| s.importer.devices}.flatten.uniq
      @databases = Logjam.database_config
      @database_keys = (%w(default) + (@databases.keys - %w(default)))
    end

    def generate_frontend
      indented(0, "frontend")
      indented(1, "endpoints")
      indented(2, "subscriber")
      indented(3, "router = \"tcp://%s:9604\"" % [Logjam.bind_ip_for_zmq_spec])
      indented(3, "pull = \"tcp://%s:9605\"" % [Logjam.bind_ip_for_zmq_spec])
      indented(3, "pub = \"tcp://%s:9651\"" % [Logjam.bind_ip_for_zmq_spec])
      indented(2, "bindings")
      @endpoints.each do |p|
        indented(3, "bind = \"%s\"" % [p])
      end
      indented(2, "livestream")
      indented(3, "pub = \"tcp://%s:9607\"" % [Logjam.bind_ip_for_zmq_spec])
      indented(1, "threads")
      indented(2, "subscribers = %d" % [Logjam.importer_subscriber_threads])
      indented(2, "parsers = %d" % [Logjam.importer_parser_threads])
      indented(2, "updaters = %d" % [Logjam.importer_updater_threads])
      indented(2, "writers = %d" % [Logjam.importer_writer_threads])
      indented(2, "zmq_io = %d" % [Logjam.importer_io_threads])
    end

    def generate_backend
      indented(0, "backend")
      generate_databases
      generate_defaults
      generate_streams
    end

    def generate_databases
      indented(1, "databases")
      # TODO: make timeouts configurable and add user and password
      timeouts = "connectTimeoutMS=5000&socketTimeoutMS=60000"
      @database_keys.each do |name|
        db = @databases[name]
        connection_uri = "db = \"mongodb://%s:%d/?%s\"" % [db['host'], db['port'], timeouts]
        indented(2, connection_uri)
      end
    end

    def generate_defaults
      indented(1, "defaults")
      indented(2, "import_threshold = %d" % Logjam.import_threshold)
      unless Logjam.ignored_request_uri.blank?
        indented(2, "ignored_request_uri = \"%s\"" % Logjam.ignored_request_uri)
      end
      indented(2, "backend_only_requests = \"%s\"" % Logjam.backend_only_requests)
      indented(2, "sampling_rate_400s = %s" % Logjam.sampling_rate_400s.to_f.to_s)
    end

    def generate_streams
      indented(1, "streams")
      @streams.values.each do |s|
        indented(2, s.importer_exchange_name.sub(/^request-stream-/,''))
        if (s.database != "default")
          indented(3, "db = %d" % [@database_keys.index(s.database)])
        end
        if s.import_threshold != Logjam.import_threshold || !s.import_thresholds.blank?
          indented(3, "import_threshold = %d" % s.import_threshold)
          s.import_thresholds.each do |prefix, value|
            indented(4, "prefix = \"%s\"" % [prefix])
            indented(5, "threshold = %d" % [value])
          end
        end
        if s.sampling_rate_400s != Logjam.sampling_rate_400s
          indented(3, "sampling_rate_400s = #{s.sampling_rate_400s.to_f}")
        end
        if s.backend_only_requests != Logjam.backend_only_requests
          indented(3, "backend_only_requests = \"%s\"" % s.backend_only_requests)
        end
        unless s.api_requests.empty?
          indented(3, "api_requests = \"%s\"" % s.api_requests.join(','))
        end
      end
    end

    def generate_metrics
      indented(0, "metrics")
      %w(time call memory heap frontend dom).each do |t|
        generate_resource(t)
      end
    end

    def generate_resource(t)
      indented(1, t)
      Resource.resources_for_type(t.to_sym).sort.each do |r|
        indented(2, r)
      end
    end

    def generate_statsd
      indented(0, "statsd")
      indented(1, "endpoint = \"%s\"" % Logjam.statsd_endpoint) if Logjam.statsd_endpoint
      indented(1, "namespace = \"%s\"" % Logjam.statsd_namespace)
    end

    def indented(level, s)
      @io.print(' ' * (level * 4))
      @io.puts s
    end
  end
end

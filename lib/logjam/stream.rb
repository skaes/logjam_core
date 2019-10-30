module Logjam
  class Stream
    attr_reader :name, :app, :env

    cattr_accessor :frontend_page
    self.frontend_page = ->(s){true}

    def initialize(name, &block)
      @name = name
      @tag = "development"
      parts = name.split('-')
      @env = parts.pop
      @app = parts.join('-')
      raise "logjam stream configuration error: missing application name #{@app}" unless @app
      raise "logjam stream configuration error: missing environment name #{@env}" unless @env
      instance_eval(&block) if block_given?
    end

    def tag(*args)
      @tag = args.first if args.first
      @tag
    end

    def forward?
      false
    end

    def workers(*args)
      @workers = [1, args.first.to_i].max if args.first
      @workers || 1
    end

    def database(*args)
      @database = args.first if args.first
      @database || "default"
    end

    def database_number
      Logjam.database_number(database)
    end

    def frontend_page(*args)
      @frontend_page = args.first if args.first
      @frontend_page || self.class.frontend_page
    end

    def ignored_request_uri(*args)
      @ignored_request_uri = args.first if args.first
      @ignored_request_uri ||= Logjam.ignored_request_uri
    end

    def import_threshold(*args)
      @import_threshold = args.first.to_i if args.first
      @import_threshold ||= Logjam.import_threshold
    end

    def import_thresholds(*args)
      @import_thresholds = args.first if args.first
      @import_thresholds ||= Logjam.import_thresholds
    end

    def request_cleaning_threshold(*args)
      @request_cleaning_threshold = args.first.to_i if args.first
      @request_cleaning_threshold ||= Logjam.request_cleaning_threshold
    end

    def database_cleaning_threshold(*args)
      @database_cleaning_threshold = args.first.to_i if args.first
      @database_cleaning_threshold ||= Logjam.database_cleaning_threshold
    end

    def database_flush_interval(*args)
      @database_flush_interval = args.first.to_i if args.first
      @database_flush_interval ||= Logjam.database_flush_interval
    end

    def backend_only_requests(*args)
      @backend_only_requests = args.first if args.first
      @backend_only_requests ||= Logjam.backend_only_requests
    end

    def api_requests(*args)
      @api_requests = args.first if args.first
      @api_requests
    end

    def sampling_rate_400s(*args)
      @sampling_rate_400s = args.first if args.first
      @sampling_rate_400s ||= Logjam.sampling_rate_400s
    end

    def http_buckets(*args)
      @http_buckets = (Logjam.http_buckets + args.first).sort.uniq if args.first
      @http_bucktes ||= Logjam.http_buckets
    end

    def jobs_buckets(*args)
      @jobs_buckets = (Logjam.jobs_buckets + args.first).sort.uniq if args.first
      @jobs_bucktes ||= Logjam.jobs_buckets
    end

    def page_buckets(*args)
      @page_buckets = (Logjam.page_buckets + args.first).sort.uniq if args.first
      @page_bucktes ||= Logjam.page_buckets
    end

    def ajax_buckets(*args)
      @ajax_buckets = (Logjam.ajax_buckets + args.first).sort.uniq if args.first
      @ajax_buckets ||= Logjam.ajax_buckets
    end

    def to_hash
      {
        :app => app,
        :env => env,
        :ignored_request_uri => ignored_request_uri,
        :backend_only_requests => backend_only_requests,
        :import_threshold => import_threshold,
        :import_thresholds => import_thresholds,
        :request_cleaning_threshold => request_cleaning_threshold,
        :database_name => database,
        :database_number => database_number,
        :database_cleaning_threshold => database_cleaning_threshold,
        :sampling_rate_400s => sampling_rate_400s,
        :api_requests => api_requests,
        :http_buckets => http_buckets,
        :jobs_buckets => jobs_buckets,
        :page_buckets => page_buckets,
        :ajax_buckets => ajax_buckets,
      }
    end

    class Context
      def initialize(stream)
        @stream = stream
      end

      def hosts(*args)
        @hosts = args if args.first
        @hosts
      end

      def exchange(*args)
        @exchange = args.first if args.first
        @exchange
      end

      def queue(*args)
        @queue = args.first if args.first
        @queue
      end

      def type(*args)
        @type = args.first if args.first
        @type
      end

      def port(*args)
        @port = args.first if args.first
        @port
      end

      def sub_type(*args)
        @sub_type = args.first if args.first
        @sub_type
      end

      def devices(*args)
        @devices = args.first if args.first
        @devices
      end
    end
  end
end

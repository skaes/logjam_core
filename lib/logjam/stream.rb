module Logjam
  class Stream
    attr_reader :name, :app, :env

    def initialize(name, &block)
      @name = name
      @tag = "development"
      @app, @env = name.split('-')
      raise "logjam stream configuration error: missing application name #{@app}" unless @app
      raise "logjam stream configuration error: missing envrironment name #{@env}" unless @env
      @importer = Importer.new
      instance_eval &block if block_given?
    end

    def importer &block
      if block_given?
        @importer.instance_eval &block
      else
        @importer
      end
    end

    def tag(*args)
      @tag = args.first if args.first
      @tag
    end

    def workers(*args)
      @workers = [1, args.first.to_i].max if args.first
      @workers || 1
    end

    module Thresholds
      def import_threshold(*args)
        @import_threshold = args.first.to_i if args.first
        @import_threshold ||= Logjam.import_threshold
      end

      def request_cleaning_threshold(*args)
        @request_cleaning_threshold = args.first.to_i if args.first
        @request_cleaning_threshold ||= Logjam.request_cleaning_threshold
      end

      def database_cleaning_threshold(*args)
        @database_cleaning_threshold = args.first.to_i if args.first
        @database_cleaning_threshold ||= Logjam.database_cleaning_threshold
      end
    end

    include Thresholds

    private

    class Context
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
    end

    class Importer < Context
      def initialize
        hosts    "localhost"
        exchange "request-stream"
        queue    "logjam3-importer-queue"
      end
    end

  end
end

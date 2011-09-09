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

    private

    class Context
      def host(*args)
        @host = args.first if args.first
        @host
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
        host     "localhost"
        exchange "request-stream"
        queue    "logjam3-importer-queue"
      end
    end

  end
end

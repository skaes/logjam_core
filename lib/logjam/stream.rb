module Logjam
  class Stream
    attr_reader :name, :app, :env

    def initialize(name, &block)
      @name = name
      @app, @env = name.split('-')
      raise "logjam stream configuration error: missing application name #{@app}" unless @app
      raise "logjam stream configuration error: missing envrironment name #{@env}" unless @env
      @importer = Importer.new
      @parser = nil
      instance_eval &block if block_given?
    end

    def parser &block
      if block_given?
        (@parser ||= Parser.new).instance_eval &block
      else
        @parser
      end
    end

    def importer &block
      if block_given?
        @importer.instance_eval &block
      else
        @importer
      end
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

    class Parser < Context
      def initialize
        host     "localhost"
        exchange "logging_exchange"
        queue    "logjam3-parser-queue"
      end

      def clusters(*args)
        @clusters = args if args.size > 0
        @clusters
      end
    end

  end
end

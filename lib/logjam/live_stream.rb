module Logjam
  class LiveStream
    attr_reader :name, :app, :env

    def initialize(env, &block)
      @name = "livestream-#{env}"
      @tag = "development"
      @host = "localhost"
      @app, @env = @name.split('-')
      raise "logjam stream configuration error: missing envrironment name #{@env}" unless @env
      instance_eval &block if block_given?
    end

    def tag(*args)
      @tag = args.first if args.first
      @tag
    end

    def host(*args)
      @host = args.first if args.first
      @host
    end

    def anomalies_host(*args)
      @anomalies_host = args.first if args.first
      @anomalies_host || "localhost"
    end

  end
end

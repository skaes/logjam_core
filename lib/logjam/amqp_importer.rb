require 'amqp'
require 'mq'
require 'date'

module Logjam

  class AMQPImporter
    RAILS_ENV = ENV['RAILS_ENV'] || 'development'

    def initialize
      @importer = MongoImporter.new("/dev/null")
    end

    def process
      EM.run do
        EM.add_periodic_timer(1) do
          @importer.flush_buffers
        end
        queue.subscribe do |header, msg|
          process_line(msg, header.routing_key)
        end
      end
    end

    def stop
      AMQP.stop { EM.stop }
      @importer.flush_buffers
    end

    private

    def queue
      @queue ||=
        begin
          config = load_config('logjam_amqp.yml')

          channel = MQ.new(AMQP::connect(:host => config[:hostname]))
          exchange = channel.topic(config[:exchange])
          queue = channel.queue("#{config[:queue]}-#{`hostname`.chomp}", :auto_delete => true, :exclusive => true)

          queue.bind(exchange, :routing_key => "logs.#")
          queue
        end
    end

    def routing_key_to_hash(routing_key)
      if m = routing_key.match(/^logs\.(.+?)\.(.+?)\..+$/)
        {:app => m[1], :env => m[2]}
      else
        {}
      end
    end

    def process_line(msg, routing_key)
      Parser.parse_line(msg) do |entry|
        app_env = routing_key_to_hash(routing_key)
        @importer.add_entry entry.to_hash.merge(app_env)
      end
    end

    def load_config(config_name)
      YAML.load_file("#{RAILS_ROOT}/config/#{config_name}")[RAILS_ENV].symbolize_keys
    end

  end
end

require 'amqp'
require 'mq'
require 'date'
require 'json'

module Logjam

  class AMQPImporter
    RAILS_ENV = ENV['RAILS_ENV'] || 'development'

    def initialize(config_name)
      @config_name = config_name
      @application = config[:app]
      @environment = config[:env]
      @importer = MongoImporter.new
    end

    def process
      EM.run do
        trap("INT") { EM.stop_event_loop }
        trap("TERM") { EM.stop_event_loop }
        @timer = EM.add_periodic_timer(1) do
          @importer.flush_buffers
        end
        queue.subscribe do |header, msg|
          process_request(msg, header.routing_key)
        end
      end
    end

    def stop
      EM.stop_event_loop
      @importer.flush_buffers
    end

    private

    def queue
      @queue ||=
        begin
          channel = MQ.new(AMQP::connect(:host => "127.0.0.1"))
          exchange = channel.topic(exchange_name, :passive => true)
          queue = channel.queue(queue_name, :auto_delete => true, :exclusive => true)
          queue.bind(exchange, :routing_key => routing_key)
        end
    end

    def exchange_name
      ["logjam-data-exchange", @application, @environment].compact.join("-")
    end

    def routing_key
      ["logs", @application, "#"].compact.join('.')
    end

    def queue_name
      ["logjam-importer-queue", @application, @environment, `hostname`.chomp].compact.join('-')
    end

    def process_request(msg, routing_key)
      entry = JSON.parse(msg)
      @importer.add_entry entry.merge!(:app => @application, :env => @environment)
    end

    def config
      @config ||= YAML.load_file("#{RAILS_ROOT}/config/logjam_amqp.yml")[@config_name].symbolize_keys
    end

  end
end

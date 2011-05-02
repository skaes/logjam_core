require 'amqp'
require 'date'
require 'json'

module Logjam

  class AMQPLogParser

    def initialize(config_name, cluster)
      @cluster = cluster
      @config_name = config_name
      @application = config[:app]
      @environment = config[:env]
    end

    def process
      EM.run do
        trap("INT") { EM.stop_event_loop }
        trap("TERM") { EM.stop_event_loop }
        parser_queue.subscribe do |header, msg|
          process_line(msg, header.routing_key)
        end
      end
    end

    def stop
      EM.stop_event_loop
    end

    private

    def importer_exchange
      @importer_exchange ||=
        begin
          channel = MQ.new(AMQP::connect(:host => "127.0.0.1"))
          channel.topic(importer_exchange_name, :durable => true, :auto_delete => false)
        end
    end

    def importer_exchange_name
      ["logjam-data-exchange", @application, @environment].compact.join("-")
    end

    def parser_queue
      @parser_queue ||=
        begin
          channel = MQ.new(AMQP::connect(config))
          channel.prefetch(1)
          exchange = channel.topic(config[:exchange], :passive => true)
          queue = channel.queue(parser_queue_name, :auto_delete => true, :exclusive => true)

          queue.bind(exchange, :routing_key => parser_routing_key)
          queue
        end
    end

    def parser_routing_key
      ["logs", @application, "#", @cluster].compact.join('.')
    end

    def parser_queue_name
      [config[:queue], @application, @environment, @cluster, `hostname`.chomp].compact.join('-')
    end

    def process_line(msg, routing_key)
      # p routing_key
      # p msg
      Parser.parse_line(msg){|entry| publish(entry.to_hash, routing_key)}
    end

    def publish(hash, key)
      # p hash
      payload = hash.to_json
      importer_exchange.publish(payload, :key => key)
    end

    def config
      @config ||= YAML.load_file("#{Rails.root}/config/logjam_amqp.yml")[@config_name].symbolize_keys
    end

  end
end

require 'amqp'
require 'date'
require 'json'

module Logjam

  class AMQPLogParser

    def initialize(config_name, cluster)
      @config = Logjam.streams[config_name]
      @cluster = cluster
      @application = @config.app
      @environment = @config.env
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
          importer_host = @config.importer.host
          puts "connecting parser output stream to rabbit on #{importer_host}"
          channel = MQ.new(AMQP::connect(:host => importer_host))
          channel.topic(importer_exchange_name, :durable => true, :auto_delete => false)
        end
    end

    def importer_exchange_name
      [@config.importer.exchange, @application, @environment].compact.join("-")
    end

    def parser_queue
      @parser_queue ||=
        begin
          parser_host = @config.parser.host
          puts "connecting parser input stream to rabbit on #{parser_host}"
          channel = MQ.new(AMQP::connect(:host => parser_host))
          channel.prefetch(1)
          exchange = channel.topic(@config.parser.exchange, :passive => true)
          queue = channel.queue(parser_queue_name, :auto_delete => true, :exclusive => true)

          queue.bind(exchange, :routing_key => parser_routing_key)
          queue
        end
    end

    def parser_routing_key
      ["logs", @application, "#", @cluster].compact.join('.')
    end

    def parser_queue_name
      [@config.parser.queue, @application, @environment, @cluster, `hostname`.chomp].compact.join('-')
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

  end
end

require 'amqp'
require 'mq'
require 'date'
require 'json'

module Logjam

  class AMQPLogParser
    RAILS_ENV = ENV['RAILS_ENV'] || 'development'

    def initialize(application)
      @application = application.blank? ? nil : application
    end

    def process
      EM.run do
        trap("INT") { EM.stop_event_loop }
        trap("TERM") { EM.stop_event_loop }
        queue.subscribe do |header, msg|
          process_line(msg, header.routing_key)
        end
      end
    end

    def stop
      EM.stop_event_loop
    end

    private

    def exchange
      @exchange ||=
        begin
          channel = MQ.new(AMQP::connect(:host => "127.0.0.1"))
          channel.topic(exchange_name, :durable => true, :auto_delete => false)
        end
    end

    def exchange_name
      ["logjam-data-exchange", @application].compact.join("-")
    end

    def queue
      @queue ||=
        begin
          channel = MQ.new(AMQP::connect(config))
          channel.prefetch(1)
          exchange =  channel.topic(config[:exchange], :passive => true)
          queue = channel.queue(queue_name, :auto_delete => true, :exclusive => true)

          queue.bind(exchange, :routing_key => routing_key)
          queue
        end
    end

    def routing_key
      ["logs", @application, "#"].compact.join('.')
    end

    def queue_name
      [config[:queue], @application, `hostname`.chomp].compact.join('-')
    end

    def process_line(msg, routing_key)
      Parser.parse_line(msg){|entry| publish(entry.to_hash, routing_key)}
    end

    def publish(hash, key)
      payload = hash.to_json
      exchange.publish(payload, :key => key)
    end

    def config
      @config ||= YAML.load_file("#{RAILS_ROOT}/config/logjam_amqp.yml")[RAILS_ENV].symbolize_keys
    end

  end
end

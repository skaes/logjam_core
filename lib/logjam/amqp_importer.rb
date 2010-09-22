require 'amqp'
require 'mq'
require 'date'
require 'json'

module Logjam

  class AMQPImporter
    RAILS_ENV = ENV['RAILS_ENV'] || 'development'

    def initialize(application)
      @importer = MongoImporter.new
      @application = application.blank? ? nil : application
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
          channel = MQ.new(AMQP::connect(config))
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

    def process_request(msg, routing_key)
      entry = JSON.parse(msg)
      app_env = Logjam.routing_key_matcher.call(routing_key) || {}
      @importer.add_entry entry.merge!(app_env)
    end

    def config
      @config ||= YAML.load_file("#{RAILS_ROOT}/config/logjam_amqp.yml")[RAILS_ENV].symbolize_keys
    end

  end
end

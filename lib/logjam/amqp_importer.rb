require 'amqp'
require 'mq'
require 'date'

module Logjam

  class AMQPImporter
    RAILS_ENV = ENV['RAILS_ENV'] || 'development'

    def initialize(application)
      @importer = MongoImporter.new("/dev/null")
      @application = application.blank? ? nil : application
    end

    def process
      EM.run do
        @timer = EM.add_periodic_timer(1) do
          @importer.flush_buffers
        end
        queue.subscribe do |header, msg|
          process_line(msg, header.routing_key)
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
          exchange = channel.topic(config[:exchange])
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
      Parser.parse_line(msg) do |entry|
        app_env = Logjam.routing_key_matcher.call(routing_key) || {}
        @importer.add_entry entry.to_hash.merge(app_env)
      end
    end

    def config
      @config ||= YAML.load_file("#{RAILS_ROOT}/config/logjam_amqp.yml")[RAILS_ENV].symbolize_keys
    end

  end
end

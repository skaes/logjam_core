require 'amqp'
require 'amqp/extensions/rabbitmq'
require 'date'
require 'json'

module Logjam

  class AMQPImporter

    def initialize(config_name)
      @stream = Logjam.streams[config_name]
      @application = @stream.app
      @environment = @stream.env
      @importer = MongoImporter.new(@stream)
      @connections = []
      @capture_file = File.open("#{Rails.root}/capture.log", "w") if ENV['LOGJAM_CAPTURE']
    end

    def process
      EM.run do
        @stream.importer.hosts.each do |host|
          settings = {:host => host, :on_tcp_connection_failure => on_tcp_connection_failure, :timeout => 1}
          connect_importer settings
        end
        trap("INT") { stop }
        trap("TERM") { stop }
        @timer = EM.add_periodic_timer(1) do
           @importer.flush_buffers
        end
      end
    end

    private

    def on_tcp_connection_failure
      Proc.new do |settings|
        puts "connection failed: #{settings[:host]}"
        EM::Timer.new(10) { connect_importer(settings) }
      end
    end

    def on_tcp_connection_loss(connection, settings)
      # reconnect in 10 seconds, without enforcement
      puts "lost connection: #{settings[:host]}"
      connection.reconnect(false, 10)
    end

    def connect_importer(settings)
      puts "connecting importer input stream to rabbit on #{settings[:host]}"
      AMQP.connect(settings) do |connection|
        puts "connected to #{settings[:host]}"
        connection.on_tcp_connection_loss(&method(:on_tcp_connection_loss))
        @connections << connection
        open_channel_and_subscribe(connection, settings[:host])
      end
    rescue EventMachine::ConnectionError => e
      puts "#{settings[:host]}: connection error: #{e}"
    end

    def open_channel_and_subscribe(connection, broker)
      AMQP::Channel.new(connection) do |channel|
        channel.auto_recovery = true
        puts "creating exchange #{exchange_name} on #{broker}"
        exchange = channel.topic(exchange_name, :durable => true, :auto_delete => false)
        puts "creating queue #{queue_name} on #{broker}"
        queue = channel.queue(queue_name, queue_options)
        puts "binding exchange #{exchange_name} to #{queue_name} on #{broker}"
        queue.bind(exchange, :routing_key => routing_key)
        puts "subscribing to queue #{queue_name} on #{broker}"
        queue.subscribe do |header, msg|
          process_request(msg, header.routing_key)
        end
      end
    end

    def queue_options
      {
        :auto_delete => true,
        :exclusive => true,
        :arguments => {
          # reap messages after 5 minutes
          "x-message-ttl" => 5 * 60 * 1000
        }
      }
    end

    def stop
      if connection = @connections.shift
        connection.close { stop }
      else
        @importer.flush_buffers
        EM.stop
      end
    end

    def exchange_name
      [@stream.importer.exchange, @application, @environment].compact.join("-")
    end

    def routing_key
      ["logs", @application, "#"].compact.join('.')
    end

    def queue_name
      [@stream.importer.queue, @application, @environment, `hostname`.chomp].compact.join('-')
    end

    def process_request(msg, routing_key)
      (c = @capture_file) && (c.puts msg)
      entry = JSON.parse(msg)
      @importer.add_entry entry
    end

  end
end

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
      @outstanding_heartbeats = Hash.new(0)
      @heartbeat_timers = {}
    end

    def process
      setup_event_system
      EM.run do
        @stream.importer.hosts.each do |host|
          settings = {:host => host, :on_tcp_connection_failure => on_tcp_connection_failure, :timeout => 5}
          connect_importer settings
        end
        trap("INT") { shutdown }
        trap("TERM") { shutdown }
        start_flushing
      end
    end

    private

    def setup_event_system
      if EM.epoll?
        EM.epoll
      elsif EM.kqueue?
        EM.kqueue
      end
    end

    def on_tcp_connection_failure
      Proc.new do |settings|
        puts "connection failed: #{settings[:host]}"
        puts "will try to again in 5 seconds"
        EM::Timer.new(5) { connect_importer(settings) }
      end
    end

    def on_tcp_connection_loss(connection, settings)
      puts "trying to reconnect: #{settings[:host]}"
      connection.reconnect(true)
    rescue EventMachine::ConnectionError => e
      puts "#{settings[:host]}: could not reconnect: #{e}"
      puts "will try to again in 5 seconds"
      EM::Timer.new(5) { on_tcp_connection_loss(connection, settings) }
    end

    def connect_importer(settings)
      puts "connecting importer input stream to rabbit on #{settings[:host]}"
      AMQP.connect(settings) do |connection|
        puts "connected to #{settings[:host]}"
        connection.on_tcp_connection_loss(&method(:on_tcp_connection_loss))
        @connections << connection
        open_channel_and_subscribe(connection, settings)
      end
    rescue EventMachine::ConnectionError => e
      # we end up here when the initial connection fails
      puts "#{settings[:host]}: connection error: #{e}"
      puts "will try to reconnect in 5 seconds"
      EM::Timer.new(5) { connect_importer settings }
    end

    def open_channel_and_subscribe(connection, settings)
      broker = settings[:host]
      AMQP::Channel.new(connection) do |channel|
        channel.auto_recovery = true

        # setup request stream
        puts "creating request stream exchange #{importer_exchange_name} on #{broker}"
        request_stream_exchange = channel.topic(importer_exchange_name, :durable => true, :auto_delete => false)
        puts "creating request stream queue #{importer_queue_name} on #{broker}"
        importer_queue = channel.queue(importer_queue_name, importer_queue_options)
        puts "binding request stream exchange #{importer_exchange_name} to #{importer_queue_name} on #{broker}"
        importer_queue.bind(request_stream_exchange, :routing_key => importer_routing_key)
        puts "subscribing to request stream queue #{importer_queue_name} on #{broker}"
        importer_queue.subscribe do |header, msg|
          process_request(msg, header.routing_key)
        end

        # setup heartbeats
        heartbeat_exchange = channel.topic(heartbeat_exchange_name, :durable => true, :auto_delete => false)
        puts "creating heartbeats queue #{heartbeat_queue_name} on #{broker}"
        heartbeat_queue = channel.queue(heartbeat_queue_name, heartbeat_queue_options)
        puts "binding heartbeats exchange #{heartbeat_exchange_name} to #{heartbeat_queue_name} on #{broker}"
        heartbeat_queue.bind(heartbeat_exchange, :routing_key => heartbeat_routing_key)
        puts "subscribing to heartbeats queue #{heartbeat_queue_name} on #{broker}"
        heartbeat_queue.subscribe do |header, msg|
          process_heartbeat(connection, settings, msg, header.routing_key)
        end
        send_heartbeats(connection, settings, heartbeat_exchange)
      end
    end

    def start_flushing
      @flushing_timer = EM.add_periodic_timer(1) do
        @importer.flush_buffers
      end
    end

    def stop_flushing
      @flushing_timer.cancel
      @importer.flush_buffers
    end

    def shutdown
      puts "shutting down"
      stop_all_heartbeats
      stop_flushing
      close_connections
    end

    def close_connections
      shutdown_timer = EM::Timer.new(5) { puts "hard exit" ; exit!(1) }
      @connections.dup.each do |connection|
        connection.close do
          @connections.delete(connection)
          if @connections.empty?
            shutdown_timer.cancel
            puts "clean exit"
            EM.stop
          end
        end
      end
    end

    def importer_exchange_name
      [@stream.importer.exchange, @application, @environment].compact.join("-")
    end

    def importer_routing_key
      ["logs", @application, "#"].compact.join('.')
    end

    def importer_queue_name
      [@stream.importer.queue, @application, @environment, hostname].compact.join('-')
    end

    def importer_queue_options
      {
        :auto_delete => true,
        :arguments => {
          # reap messages after 5 minutes
          "x-message-ttl" => 5 * 60 * 1000
        }
      }
    end

    def heartbeat_exchange_name
      "logjam3-importer-heartbeats"
    end

    def heartbeat_routing_key
      ["logjam", "heartbeat", @application, @environment, hostname, $$].compact.join('.')
    end

    def heartbeat_queue_name
      ["logjam3-importer-heartbeats", @application, @environment, hostname].compact.join('-')
    end

    def heartbeat_queue_options
      {
        :auto_delete => true,
        :arguments => {
          # reap messages after 1 minute
          "x-message-ttl" => 60 * 1000
        }
      }
    end

    def hostname
      @hostname ||= `hostname`.chomp
    end

    def process_request(msg, routing_key)
      (c = @capture_file) && (c.puts msg)
      entry = JSON.parse(msg)
      @importer.add_entry entry
    end

    def send_heartbeats(connection, settings, heartbeat_exchange)
      @outstanding_heartbeats[connection] = 0
      @heartbeat_timers[connection] = EM::PeriodicTimer.new(5) do
        if (n = @outstanding_heartbeats[connection]) > 5
          puts "missed #{n} heartbeats[#{settings[:host]}, #{connection.object_id}]"
          # the connection is presumably dead. close it hard.
          stop_heartbeats(connection)
          connection.set_comm_inactivity_timeout(5)
          @connections.delete(connection).close_connection
          connect_importer settings
        else
          puts "sending heartbeat [#{settings[:host]}, #{connection.object_id}]. outstanding: #{n}"
          @outstanding_heartbeats[connection] += 1
          heartbeat_exchange.publish("blah blah blah", :routing_key => heartbeat_routing_key)
        end
      end
    end

    def stop_all_heartbeats
      @heartbeat_timers.keys.each {|connection| stop_heartbeats(connection)}
    end

    def stop_heartbeats(connection)
      @heartbeat_timers.delete(connection).cancel
      @outstanding_heartbeats.delete(connection)
    end

    def process_heartbeat(connection, settings, msg, routing_key)
      n = (@outstanding_heartbeats[connection] -= 1)
      puts "received heartbeat  [#{settings[:host]}, #{connection.object_id}]. outstanding: #{n}"
    end
  end
end

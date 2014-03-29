require 'amqp'
require 'amqp/extensions/rabbitmq'
require 'logjam/eventmachine'
require 'date'
require 'oj'

module Logjam

  class AMQPImporter

    include Helpers
    include ReparentingTimer

    def initialize(stream)
      @stream = stream
      @application = @stream.app
      @environment = @stream.env
      @app_string = "request-stream-#{@application}-#{@environment}"
      @context = EM::ZeroMQ::Context.new(1)
      @request_processor = RequestProcessorServer.new(@stream, @context)
      @event_processor = EventProcessor.new(@stream)
      @connections = []
      @capture_file = File.open("#{Rails.root}/capture-#{$$}.log", "wb") if ENV['LOGJAM_CAPTURE']
      @outstanding_heartbeats = Hash.new(0)
      @heartbeat_timers = {}
      setup_zmq_push_socket
    end

    def setup_zmq_push_socket
      log_info "setting up push socket"
      @socket = @context.socket(ZMQ::PUSH)
      @socket.setsockopt(ZMQ::LINGER, 0) # milliseconds
      @socket.setsockopt(ZMQ::SNDHWM, 1)
      socket_spec = "tcp://localhost:9650"
      rc = @socket.connect(socket_spec)
      unless ZMQ::Util.resultcode_ok? rc
        log_error("Could not connect to push socket %s: %s(%d)" % [socket_spec, ZMQ::Util.error_string, ZMQ::Util.errno])
      end
    end

    def close_zmq_push_socket
      @socket.close
    end

    def forward_msg_on_zmq_socket(msg, routing_key)
      @socket.send_msg(@app_string, routing_key, msg)
    end

    def process
      @stream.importer.hosts.each do |host|
        settings = {:host => host, :on_tcp_connection_failure => on_tcp_connection_failure, :timeout => 5}
        connect_importer settings
      end
      trap_signals
      shutdown_if_reparented_to_root_process_or_heap_insanity_detected
    end

    private

    def trap_signals
      trap("CHLD", "DEFAULT")
      trap("EXIT", "DEFAULT")
      trap("INT")  { }
      trap("TERM") { shutdown }
    end

    def on_tcp_connection_failure
      Proc.new do |settings|
        log_error "connection failed: #{settings[:host]}"
        log_info "will try to again in 5 seconds"
        EM::Timer.new(5) { connect_importer(settings) }
      end
    end

    def on_tcp_connection_loss(connection, settings)
      log_info "trying to reconnect: #{settings[:host]}"
      connection.reconnect(true)
    rescue EventMachine::ConnectionError => e
      log_error "#{settings[:host]}: could not reconnect: #{e}"
      log_info "will try to again in 5 seconds"
      EM::Timer.new(5) { on_tcp_connection_loss(connection, settings) }
    end

    def connect_importer(settings)
      log_info "connecting importer input stream to rabbit on #{settings[:host]}"
      AMQP.connect(settings) do |connection|
        log_info "connected to #{settings[:host]}"
        connection.on_tcp_connection_loss(&method(:on_tcp_connection_loss))
        @connections << connection
        open_channel_and_subscribe(connection, settings)
      end
    rescue EventMachine::ConnectionError => e
      # we end up here when the initial connection fails
      log_error "#{settings[:host]}: connection error: #{e}"
      log_info "will try to reconnect in 5 seconds"
      EM::Timer.new(5) { connect_importer settings }
    end

    def open_channel_and_subscribe(connection, settings)
      broker = settings[:host]
      AMQP::Channel.new(connection) do |channel|
        channel.auto_recovery = true

        # setup request stream
        log_info "creating request stream exchange #{importer_exchange_name} on #{broker}"
        request_stream_exchange = channel.topic(importer_exchange_name, :durable => true, :auto_delete => false)

        log_info "creating request stream queue #{importer_queue_name} on #{broker}"
        importer_queue = channel.queue(importer_queue_name, importer_queue_options)

        log_info "binding request stream exchange #{importer_exchange_name} to #{importer_queue_name} on #{broker}"
        # importer_queue.bind(request_stream_exchange, :routing_key => "#")
        importer_queue.bind(request_stream_exchange, :routing_key => importer_routing_key)
        importer_queue.bind(request_stream_exchange, :routing_key => events_routing_key)
        importer_queue.bind(request_stream_exchange, :routing_key => js_exceptions_routing_key)

        log_info "subscribing to request stream queue #{importer_queue_name} on #{broker}"
        importer_queue.subscribe do |header, msg|
          begin
            case header.routing_key
            when /^logs/
              process_request(msg, header.routing_key)
            when /^events/
              process_event(msg, header.routing_key)
            when /^javascript/
              process_js_exception(msg, header.routing_key)
            end
          rescue => e
            log_error "error during request processing: #{e.class}(#{e})"
          end
        end

        # setup heartbeats
        heartbeat_exchange = channel.topic(heartbeat_exchange_name, :durable => true, :auto_delete => false)

        log_info "creating heartbeats queue #{heartbeat_queue_name} on #{broker}"
        heartbeat_queue = channel.queue(heartbeat_queue_name, heartbeat_queue_options)

        log_info "binding heartbeats exchange #{heartbeat_exchange_name} to #{heartbeat_queue_name} on #{broker}"
        heartbeat_queue.bind(heartbeat_exchange, :routing_key => heartbeat_routing_key)

        log_info "subscribing to heartbeats queue #{heartbeat_queue_name} on #{broker}"
        heartbeat_queue.subscribe do |header, msg|
          process_heartbeat(connection, settings, msg, header.routing_key)
        end
        send_heartbeats(connection, settings, heartbeat_exchange)
      end
    end

    def shutdown
      stop_reparenting_timer
      stop_all_heartbeats
      close_connections
      close_zmq_push_socket
    end

    def close_connections
      log_info "shutting down amqp connections"
      shutdown_timer = EM::Timer.new(5) { log_info "hard exit" ; exit!(1) }
      @connections.dup.each do |connection|
        connection.close do
          @connections.delete(connection)
          if @connections.empty?
            shutdown_timer.cancel
            log_info "clean exit"
            exit!(0)
            # TODO: figure out why EM.stop doesn't work
            # EM.stop
          end
        end
      end
    end

    def importer_exchange_name
      @stream.importer_exchange_name
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
          # reap messages after 1 minute
          "x-message-ttl" => 60 * 1000
        }
      }
    end

    def events_routing_key
      ["events", @application, @environment].compact.join('.')
    end

    def js_exceptions_routing_key
      ["javascript", @application, @environment].compact.join('.')
    end

    def heartbeat_exchange_name
      "logjam3-importer-heartbeats"
    end

    def heartbeat_routing_key
      ["logjam", "heartbeat", @application, @environment, hostname, $$].compact.join('.')
    end

    def heartbeat_queue_name
      ["logjam3-heartbeats", @application, @environment, hostname, $$].compact.join('-')
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
      if @capture_file
        @capture_file.puts msg
      else
        forward_msg_on_zmq_socket(msg, routing_key)
        request = Oj.load(msg, :mode => :compat)
        @request_processor.process(request)
      end
    end

    def process_event(msg, routing_key)
      forward_msg_on_zmq_socket(msg, routing_key)
      event = Oj.load(msg, :mode => :compat)
      @event_processor.process(event)
    end

    def process_js_exception(msg, routing_key)
      forward_msg_on_zmq_socket(msg, routing_key)
      exception = Oj.load(msg, :mode => :compat)
      @request_processor.process_js_exception(exception)
    end

    def send_heartbeats(connection, settings, heartbeat_exchange)
      @outstanding_heartbeats[connection] = 0
      @heartbeat_timers[connection] = EM::PeriodicTimer.new(5) do
        if (n = @outstanding_heartbeats[connection]) > 5
          log_info "missed #{n} heartbeats[#{settings[:host]}, #{connection.object_id}]"
          # the connection is presumably dead. close it hard.
          stop_heartbeats(connection)
          connection.set_comm_inactivity_timeout(5)
          @connections.delete(connection).close_connection
          connect_importer settings
        else
          log_info "sending heartbeat [#{settings[:host]}, #{connection.object_id}]. outstanding: #{n}"
          @outstanding_heartbeats[connection] += 1
          heartbeat_exchange.publish("blah blah blah", :routing_key => heartbeat_routing_key)
        end
      end
    end

    def stop_all_heartbeats
      log_info "stopping heartbeats"
      @heartbeat_timers.keys.each {|connection| stop_heartbeats(connection)}
    end

    def stop_heartbeats(connection)
      @heartbeat_timers.delete(connection).cancel
      @outstanding_heartbeats.delete(connection)
    end

    def process_heartbeat(connection, settings, msg, routing_key)
      n = (@outstanding_heartbeats[connection] -= 1)
      log_info "received heartbeat  [#{settings[:host]}, #{connection.object_id}]. outstanding: #{n}"
    end
  end
end

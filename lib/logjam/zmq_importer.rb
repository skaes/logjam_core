require 'amqp'
require 'amqp/extensions/rabbitmq'
require 'date'
require 'oj'

module Logjam

  class ZMQImporter

    include Helpers
    include ReparentingTimer

    def initialize(stream)
      @stream       = stream
      @application  = @stream.app
      @environment  = @stream.env
      @context      = EM::ZeroMQ::Context.new(1)
      @request_processor = RequestProcessorServer.new(@stream, @context)
      @event_processor = EventProcessor.new(@stream)
      @capture_file = File.open("#{Rails.root}/capture-#{$$}.log", "w") if ENV['LOGJAM_CAPTURE']
    end

    def process
      setup_connection
      trap_signals
      shutdown_if_reparented_to_root_process
    end

    private

    def trap_signals
      trap("CHLD", "DEFAULT")
      trap("EXIT", "DEFAULT")
      trap("INT")  { }
      trap("TERM") { shutdown }
    end

    def setup_connection
      @socket = @context.socket(ZMQ::SUB)
      @socket.setsockopt(ZMQ::LINGER, 500)
      @socket.setsockopt(ZMQ::RCVHWM, 5000)
      @socket.setsockopt(ZMQ::SUBSCRIBE, requests_subscription_key)
      @socket.setsockopt(ZMQ::SUBSCRIBE, events_subscription_key)
      @stream.importer.hosts.each do |host|
        address = "tcp://#{host}:9606"
        log_info "connecting to #{address}"
        @socket.connect(address)
      end
      @socket.on(:message) do |p1, p2|
        key = p1.copy_out_string; p1.close
        msg = p2.copy_out_string; p2.close
        # puts key, msg
        case key
        when /^logs/
          process_request(msg)
        when /^events/
          process_event(msg)
        end
      end
    end

    def shutdown
      stop_reparenting_timer
      log_info "shutting down zmq importer"
      @socket.setsockopt(ZMQ::UNSUBSCRIBE, requests_subscription_key)
      @socket.unbind
      log_info "stopping processor"
      @request_processor.stop
      EM.stop
      # exit immediately to avoid: Assertion failed: ok (mailbox.cpp:79)
      log_info "exiting zmq_worker"
      exit!(0)
    end

    def requests_subscription_key
      # TODO: should env really be part of the subscription key?
      ["logs", @application, @environment].compact.join('.')
    end

    def events_subscription_key
      # TODO: should env really be part of the subscription key?
      ["events", @application, @environment].compact.join('.')
    end

    def process_request(msg)
      (c = @capture_file) && (c.puts msg)
      request = Oj.load(msg, :mode => :compat)
      @request_processor.process(request)
    end

    def process_event(msg)
      event = Oj.load(msg, :mode => :compat)
      @event_processor.process(event)
    end
  end
end

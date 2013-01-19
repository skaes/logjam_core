require 'amqp'
require 'amqp/extensions/rabbitmq'
require 'date'
require 'oj'

module Logjam

  class ZMQImporter

    include LogWithProcessId

    def initialize(stream)
      @stream       = stream
      @application  = @stream.app
      @environment  = @stream.env
      @context      = EM::ZeroMQ::Context.new(1)
      @processor    = RequestProcessorServer.new(@stream, @context)
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

    def shutdown_if_reparented_to_root_process
      EM.add_periodic_timer(1) do
        if Process.ppid == 1
          begin
            log_error "refusing to become an orphan. committing suicide."
          ensure
            exit!(1)
          end
        end
      end
    end

    def setup_connection
      @socket = @context.socket(ZMQ::SUB)
      @socket.setsockopt(ZMQ::LINGER, 500)
      @socket.setsockopt(ZMQ::RCVHWM, 5000)
      @socket.setsockopt(ZMQ::SUBSCRIBE, subscription_key)
      @stream.importer.hosts.each do |host|
        address = "tcp://#{host}:9606"
        log_info "connecting to #{address}"
        @socket.connect(address)
      end
      @socket.on(:message) do |p1, p2|
        key = p1.copy_out_string; p1.close
        msg = p2.copy_out_string; p2.close
        # puts key, msg
        process_request(msg)
      end
    end

    def shutdown
      @socket.setsockopt(ZMQ::UNSUBSCRIBE, subscription_key)
      @socket.unbind
      EM.stop
    end

    def subscription_key
      # TODO: should env really be part of the subscription key?
      ["logs", @application, @environment].compact.join('.')
    end

    def process_request(msg)
      (c = @capture_file) && (c.puts msg)
      request = Oj.load(msg, :mode => :compat)
      @processor.process_request(request)
    end

  end
end

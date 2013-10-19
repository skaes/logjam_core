require 'logjam/eventmachine'
require 'em-zeromq'

module Logjam
  class ImporterManager
    include Helpers

    def initialize(stream)
      @stream = stream
      @application = @stream.app
      @environment = @stream.env
      @database_flush_interval = @stream.database_flush_interval
      log_info "creating ZMQ context"
      @zmq_context = ZMQ::Context.new(1)
      @importer = MongoImporter.new(@stream, @zmq_context)
    end

    def process
      setup_event_system
      EM.run do
        start_flushing
        trap_signals
        start_workers
      end
    end

    def setup_event_system
      if EM.epoll?
        EM.epoll?
      elsif EM.kqueue?
        EM.kqueue
      end
    end

    def trap_signals
      trap("INT") { shutdown }
      trap("TERM") { shutdown }
    end

    def shutdown
      stop_flushing
      flush_buffers
      stop_workers
      @importer.stop
      log_info "closing ZMQ context"
      @zmq_context.terminate
      log_info "stopping eventmachine"
      EM.stop
      # exit immediately to avoid:
      # Assertion failed: (errno != EINVAL), function _RunKqueueOnce, file em.cpp, line 608.
      log_info "exiting worker manager"
      exit(0)
    end

    def start_flushing
      @flushing_timer = EM.add_periodic_timer(@database_flush_interval) do
        flush_buffers
      end
    end

    def stop_flushing
      @flushing_timer.cancel if @flushing_timer
    end

    def flush_buffers
      if @proxy
        states = nil
        ms1 = Benchmark.ms { states = @proxy.reset_state }
        ms2 = Benchmark.ms { @importer.process(states) }
        log_info("flushtime %4d ms (collect:%.1f, process: %.1f)" % [(ms1+ms2).to_i, ms1, ms2])
      end
    end

    def start_workers
      @proxy = RequestProcessorProxy.new(@stream, @zmq_context)
    end

    def stop_workers
      @proxy.shutdown if @proxy
    end
  end
end

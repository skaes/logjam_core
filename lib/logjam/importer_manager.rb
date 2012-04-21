module Logjam
  class ImporterManager
    include LogWithProcessId

    def initialize(stream)
      @stream = stream
      @application = @stream.app
      @environment = @stream.env
      @importer = MongoImporter.new(@stream)
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
      EM.stop
    end

    def start_flushing
      @flushing_timer = EM.add_periodic_timer(1) do
        flush_buffers
      end
    end

    def stop_flushing
      @flushing_timer.cancel if @flushing_timer
    end

    def flush_buffers
      if @proxy
        states = @proxy.reset_state
        @importer.process(states)
      end
    end

    def start_workers
      @proxy = RequestProcessorProxy.new(@stream)
    end

    def stop_workers
      @proxy.shutdown if @proxy
    end
  end
end

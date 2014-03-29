require 'em-zeromq'

module Logjam
  class RequestProcessorServer

    include Helpers

    def initialize(stream, zmq_context)
      @stream = stream
      @processors = {}
      @gc_time_last = nil
      @context = zmq_context
      setup_connection
    end

    def stop
      log_info "closing state connection"
      @socket.unbind if @socket
    end

    def id
      Process.pid
    end

    def socket_file_name
      "#{Rails.root}/tmp/sockets/state-#{@stream.app}-#{@stream.env}-#{id}.ipc"
    end

    def setup_connection
      log_info "setting up state connection #{id}"
      @socket = @context.socket(ZMQ::REP)
      @socket.setsockopt(ZMQ::LINGER, 500) # milliseconds
      @socket.on(:message) do |*parts|
        parts.each(&:close)
        on_reset_state_received
      end
      rc = @socket.bind("ipc:///#{socket_file_name}")
      unless ZMQ::Util.resultcode_ok? rc
        log_error("Could not bind to socket %s: %s (%d)" % [socket_file_name, ZMQ::Util.error_string, ZMQ::Util.errno])
      end
    end

    def on_reset_state_received
      message = reset_state
      log_info "sending processor state"
      if @socket.send_msg(message)
        log_info "sent request processor state"
      else
        log_error "sending request processor state failed"
      end
    end

    def reset_state
      log_info "received reset state"
      if GC.respond_to?(:heap_slots) && GC.respond_to?(:heap_slots_live_after_last_gc)
        gc_time_now = GC.time/1000.0 # ms
        gc_time_used = @gc_time_last ? gc_time_now - @gc_time_last : 0.0
        log_info("slots: %6d, live: %6d, gc_time: %06.2f ms" % [GC.heap_slots, GC.heap_slots_live_after_last_gc, gc_time_used])
        @gc_time_last = gc_time_now
      end
      info = []
      @processors.each do |db_name, processor|
        info << [db_name, processor.reset_state]
      end
      clean_old_processors
      Marshal.dump(info)
    end

    def process(r)
      # log_info "received request"
      # log_info r.inspect
      processor(r).add(r)
    rescue => e
      log_error "failed to process request: #{e.class}(#{e})"
      log_error r.inspect
    end

    def process_js_exception(exception)
      processor(exception).add_js_exception(exception)
    rescue => e
      log_error "failed to process JS exception: #{e.class}(#{e})"
      log_error exception.inspect
    end

    def processor(hash)
      dbname = Logjam.db_name(hash["started_at"], @stream.app, @stream.env)
      @processors[dbname] ||=
        begin
          log_info "creating request processor #{dbname}"
          Logjam.ensure_known_database(dbname)
          database = Logjam.connection_for(dbname).db(dbname)
          requests_collection = Requests.ensure_indexes(database["requests"])
          RequestProcessor.new(@stream, requests_collection)
        end
    end

    def clean_old_processors
      current_db_name = Logjam.db_name(Date.today, @stream.app, @stream.env)
      @processors.delete_if{|db_name,_| db_name != current_db_name}
    end
  end
end

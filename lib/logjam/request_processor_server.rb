require 'em-zeromq'

module Logjam
  class RequestProcessorServer

    include Helpers

    def initialize(stream, zmq_context = nil)
      @stream = stream
      @processors = {}
      @context = zmq_context || EM::ZeroMQ::Context.new(1)
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
      @socket.bind("ipc:///#{socket_file_name}")
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
      log_info("slots: %d, live: %d" % [GC.heap_slots, GC.heap_slots_live_after_last_gc])
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
      log_info "failed to process request: #{e.class}(#{e})"
      log_info r.inspect
    end

    def process_js_exception(exception)
      processor(exception).add_js_exception(exception)
    rescue => e
      log_info "failed to process JS exception: #{e.class}(#{e})"
      log_info exception.inspect
    end

    def processor(hash)
      dbname = Logjam.db_name(hash["started_at"], @stream.app, @stream.env)
      @processors[dbname] ||=
        begin
          log_info "creating request processor #{dbname}"
          Logjam.ensure_known_database(dbname)
          database = Logjam.connection_for(dbname).db(dbname)
          requests_collection, old_format = Requests.ensure_indexes(database["requests"])
          RequestProcessor.new(@stream, requests_collection, old_format)
        end
    end

    def clean_old_processors
      current_db_name = Logjam.db_name(Date.today, @stream.app, @stream.env)
      @processors.delete_if{|db_name,_| db_name != current_db_name}
    end
  end
end

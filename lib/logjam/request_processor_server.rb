require 'em-zeromq-mri'

module Logjam
  class RequestProcessorServer

    include LogWithProcessId

    def initialize(app, env, id)
      @app = app
      @env = env
      @processors = {}
      trap_signals
      @context = EM::ZeroMQ::Context.new(1)
      setup_state_connection(id)
      setup_requests_connection
    end

    def trap_signals
      trap("CHLD", "DEFAULT")
      trap("EXIT", "DEFAULT")
#       trap("INT") do
#         begin
#           log_info "ignored interrupt"
#         rescue Exception
#         end
#       end
      trap("TERM"){ terminate }
      trap("INT"){ }
    end

    def terminate
      log_error "terminating"
      @state_socket.close
      @requests_socket.close
      EM.stop_event_loop
      exit!
    end

    class StateHandler
      def initialize(server)
        @server = server
      end
      def on_readable(socket, messages)
        @server.reset_state_received(messages)
      end
    end

    def setup_state_connection(id)
      log_info "setting up state connection #{id}"
      @state_socket = @context.socket(ZMQ::REP)
      @state_socket.setsockopt(ZMQ::LINGER, 500) # milliseconds
      @state_connection = @context.bind(@state_socket, "ipc:///#{Rails.root}/tmp/sockets/state-#{@app}-#{@env}-#{id}", StateHandler.new(self))
    end

    def reset_state_received(messages)
      message = reset_state
      if @state_connection.socket.send_string(message, ZMQ::NOBLOCK)
        log_info "sent request processor state"
      else
        log_error "sending request processor state failed"
      end
    end

    def reset_state
      log_info "received reset state"
      info = []
      @processors.each do |dbname, processor|
        info << [dbname, processor.reset_state]
      end
      Marshal.dump(info)
    end

    class RequestsHandler
      def initialize(server)
        @server = server
      end
      def on_readable(socket, messages)
        @server.requests_received(messages)
      end
    end

    def setup_requests_connection
      log_info "setting up requests connection"
      @requests_socket = @context.socket(ZMQ::PULL)
      @requests_socket.setsockopt(ZMQ::LINGER, 500) # millicesonds
      @requests_connection = @context.connect(@requests_socket, "ipc:///#{Rails.root}/tmp/sockets/requests-#{@app}-#{@env}", RequestsHandler.new(self))
    end

    def requests_received(messages)
      messages.each do |m|
        r = Marshal.load(m.copy_out_string)
        process_request(r)
      end
    end

    def process_request(r)
      # log_info "received request"
      # log_info r.inspect
      processor(r).add(r)
    end

    def processor(hash)
      date_str = hash["started_at"][0..9]
      dbname = Logjam.db_name(date_str, @app, @env)
      @processors[dbname] ||=
        begin
          log_info "creating request processor #{dbname}"
          database = Logjam.mongo.db(dbname)
          requests_collection = database["requests"]
          RequestProcessor.new(requests_collection)
        end
    end

  end
end

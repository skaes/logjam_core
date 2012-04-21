require 'em-zeromq-mri'

module Logjam
  class RequestProcessorServer

    include LogWithProcessId

    def initialize(stream)
      @app = stream.app
      @env = stream.env
      @processors = {}
      @context = EM::ZeroMQ::Context.new(1)
      setup_connection
    end

    def id
      Process.pid
    end

    def socket_spec
      "ipc:///#{Rails.root}/tmp/sockets/state-#{@app}-#{@env}-#{id}"
    end

    class StateHandler
      def initialize(server)
        @server = server
      end
      def on_readable(socket, messages)
        @server.on_reset_state_received(messages)
      end
    end

    def setup_connection
      log_info "setting up state connection #{id}"
      @socket = @context.socket(ZMQ::REP)
      @socket.setsockopt(ZMQ::LINGER, 500) # milliseconds
      @connection = @context.bind(@socket, socket_spec, StateHandler.new(self))
    end

    def on_reset_state_received(messages)
      message = reset_state
      if @connection.socket.send_string(message, ZMQ::NOBLOCK)
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
          Logjam.ensure_known_database(dbname)
          database = Logjam.mongo.db(dbname)
          requests_collection = Requests.ensure_indexes(database["requests"])
          RequestProcessor.new(requests_collection)
        end
    end

  end
end

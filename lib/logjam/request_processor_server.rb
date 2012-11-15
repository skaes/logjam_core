require 'em-zeromq-mri'

module Logjam
  class RequestProcessorServer

    include LogWithProcessId

    def initialize(stream)
      @stream = stream
      @processors = {}
      @context = EM::ZeroMQ::Context.new(1)
      setup_connection
    end

    def id
      Process.pid
    end

    def socket_file_name
      "#{Rails.root}/tmp/sockets/state-#{@stream.app}-#{@stream.env}-#{id}.ipc"
    end

    class ResetStateHandler
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
      @connection = @context.bind(@socket, "ipc:///#{socket_file_name}", ResetStateHandler.new(self))
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
      @processors.each do |db_name, processor|
        info << [db_name, processor.reset_state]
      end
      clean_old_processors
      Marshal.dump(info)
    end

    def process_request(r)
      # log_info "received request"
      # log_info r.inspect
      processor(r).add(r)
    rescue => e
      log_info "failed to process request: #{e.class}(#{e})"
      log_info r.inspect
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

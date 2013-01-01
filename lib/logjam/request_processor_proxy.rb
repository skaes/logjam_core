require 'ffi-rzmq'
require 'em-zeromq'
require 'fileutils'

module Logjam

  class RequestProcessorProxy

    include LogWithProcessId

    def initialize(stream)
      @stream = stream
      @app = @stream.app
      @env = @stream.env
      @servers = []
      @sockets = {}
      @context = ZMQ::Context.new(1)
      $PROGRAM_NAME = "logjam-importer-#{@app}-#{@env}"
      clean_old_sockets
      start_servers(@stream.workers)
    end

    def reset_state
      states = []
      @sockets.each_value do |socket|
        socket.send_string("RESET_STATE")
        data = ""
        if socket.recv_string(data) < 0
          log_error "failed to receive reset state data"
        else
          states << Marshal.load(data)
        end
      end
      states
    end

    def socket_file_name(pid)
      "#{Rails.root}/tmp/sockets/state-#{@app}-#{@env}-#{pid}.ipc"
    end

    def clean_old_sockets
      log_info "cleaning old sockets"
      FileUtils.rm_f(Dir.glob(socket_file_name("*")))
    end

    def start_servers(n)
      trap("CHLD"){ child_status_change }
      n.times do
        fork_worker
      end
    end

    def fork_worker
      log_info "forking worker"
      pid = EM.fork_reactor do
        worker_pid = Process.pid
        log_info "started worker #{worker_pid}"
        $PROGRAM_NAME = "logjam-worker-#{@app}-#{@env}"
        case @stream.importer.type
        when :amqp
          AMQPImporter.new(@stream).process
        when :zmq
          ZMQImporter.new(@stream).process
        end
      end
      add_server(pid)
    end

    def child_status_change
      log_info "CHLD status change: #{@sockets.keys.sort.inspect}"
      if (pid = wait_child) && remove_server(pid)
        log_error "Child worker #{pid} died"
        fork_worker
      end
    end

    def wait_child
      log_info "waiting for child"
      pid = Process.wait(-1, Process::WNOHANG)
      log_info "process terminated: #{pid || 'unknown pid'}"
      pid
    rescue Errno::ECHILD
      log_error "No child to wait for!"
      nil
    end

    def remove_server(pid)
      if socket = @sockets.delete(pid)
        log_info "removing server #{pid}"
        socket.close
        FileUtils.rm_f(socket_file_name(pid))
        log_info "removed server #{pid}"
        pid
      end
    end

    def add_server(pid)
      log_info "adding server #{pid}"
      socket = @context.socket(ZMQ::REQ)
      socket.setsockopt(ZMQ::LINGER, 100)
      socket.connect("ipc:///#{socket_file_name(pid)}")
      @sockets[pid] = socket
      log_info "added server #{pid}"
    end

    def shutdown
      log_info "shutting down workers"
      trap("CHLD"){}
      @sockets.keys.dup.each do |pid|
        begin
          Process.kill("TERM", pid)
          Process.wait(pid)
        rescue Exception
          log_error "waiting for child worker #{pid} raised #{$!}"
        ensure
          remove_server(pid)
        end
      end
      log_info "closing ZMQ context"
      @context.terminate
      log_info "worker shutdown completed"
    end
  end
end

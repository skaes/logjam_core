require 'zmq'
require 'fileutils'

module Logjam

  class RequestProcessorProxy

    include LogWithProcessId

    def initialize(app, env, num_servers=1)
      @app = app
      @env = env
      @servers = []
      @state_sockets = {}
      @context = ZMQ::Context.new(1)
      $PROGRAM_NAME = "logjam-importer-#{@app}-#{@env}"
      clean_old_sockets
      start_servers(num_servers)
      create_push_socket
    end

    def process_request(request)
      @push_socket.send(Marshal.dump(request)) if @push_socket
    rescue
      log_error "could not send request: #{$!.class}"
    end

    def create_push_socket
      log_info "creating requests push socket"
      @push_socket = @context.socket(ZMQ::PUSH)
      @push_socket.setsockopt(ZMQ::LINGER, 100)
      @push_socket.bind("ipc:///#{Rails.root}/tmp/sockets/requests-#{@app}-#{@env}")
      log_info "created requests push socket"
    end

    def reset_state
      states = []
      @state_sockets.each_value do |socket|
        socket.send("RESET_STATE")
        data = socket.recv
        states << Marshal.load(data)
      end
      states
    end

    def clean_old_sockets
      log_info "cleaning old sockets"
      FileUtils.rm_f("#{Rails.root}/tmp/sockets/requests-#{@app}-#{@env}")
      FileUtils.rm_f(Dir.glob("#{Rails.root}/tmp/sockets/state-#{@app}-#{@env}-*"))
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
        log_info "started worker #{Process.pid}"
        $PROGRAM_NAME = "logjam-worker-#{@app}-#{@env}"
        RequestProcessorServer.new(@app, @env, Process.pid)
      end
      add_server(pid)
    end

    def child_status_change
      log_info "CHLD status change: #{@state_sockets.keys.sort.inspect}"
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
      if socket = @state_sockets.delete(pid)
        log_info "removing server #{pid}"
        socket.close
        FileUtils.rm_f("#{Rails.root}/tmp/sockets/state-#{@app}-#{@env}-#{pid}")
        log_info "removed server #{pid}"
        pid
      end
    end

    def add_server(pid)
      log_info "adding server #{pid}"
      socket = @context.socket(ZMQ::REQ)
      socket.setsockopt(ZMQ::LINGER, 100)
      socket.connect("ipc:///#{Rails.root}/tmp/sockets/state-#{@app}-#{@env}-#{pid}")
      @state_sockets[pid] = socket
      log_info "added server #{pid}"
    end

    def shutdown
      log_info "shutting down workers"
      trap("CHLD"){}
      @state_sockets.keys.dup.each do |pid|
        begin
          Process.kill("TERM", pid)
          Process.wait(pid)
        rescue Exception
          log_error "waiting for child worker #{pid} raised #{$!}"
        ensure
          remove_server(pid)
        end
      end
      log_info "closing push socket"
      @push_socket.close
      @push_socket = nil
      FileUtils.rm_f("#{Rails.root}/tmp/sockets/requests-#{@app}-#{@env}")
      @context.close
    end
  end
end

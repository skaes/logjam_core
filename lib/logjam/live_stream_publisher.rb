require 'oj'

module Logjam
  class LiveStreamPublisher
    include Helpers

    def initialize(stream, zmq_context)
      @stream = stream
      @app = stream.app
      @env = stream.env
      @socket = zmq_context.socket(ZMQ::PUSH)
      @socket.setsockopt(ZMQ::LINGER, 100)
      @socket.setsockopt(ZMQ::SNDHWM, 1000)
      @socket.connect("tcp://#{live_stream_host}:9607")
    end

    def stop
      @socket.close
    end

    def publish(modules, totals_buffer, errors_buffer)
      publish_totals(modules, totals_buffer)
      publish_errors(modules, errors_buffer)
    end

    def live_stream_host
      Logjam.streams["livestream-#{Rails.env}"].host
    end

    NO_REQUEST = {"count" => 0}

    def publish_totals(modules, totals_buffer)
      # always publish something every second to the perf data exchange
      modules.each { |p| send_data(p, totals_buffer[p] || NO_REQUEST) }
    end

    def publish_errors(modules, errors_buffer)
      modules.each do |p|
        if errs = errors_buffer[p]
          # $stderr.puts errs
          send_data(p, errs)
        end
      end
    end

    def send_data(p, data)
      data = clean_published_data(data)
      app_env_key = "#{@app}-#{@env},#{p.sub(/^::/,'').downcase}"
      perf_data = Oj.dump(data, :mode => :compat)
      @socket.send_strings([app_env_key, perf_data], ZMQ::DONTWAIT)
    rescue => e
      log_error "could not publish performance/error data: #{e.class}(#{e})"
      log_backtrace(e)
      log_info data.inspect
      if data.is_a?(Hash)
        log_error "HASH data: #{data.keys.map(&:encoding)}"
      else
        log_error "ARRAY data: #{data.map{|h| h.keys.map(&:encoding)}}"
      end
      # uncomment for debugging in dev mode
      # exit!(0)
    end

    def clean_published_data(data)
      if data.is_a?(Hash)
        data.reject do |k,_|
          # k.dup.force_encoding('ASCII-8BIT') =~ /\A(callers|exceptions|js_exceptions)\./n
          k =~ /\A(callers|exceptions|js_exceptions)\./
        end
      else
        data
      end
    end
  end

end

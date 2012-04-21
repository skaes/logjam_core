require 'amqp'
require 'json'

module Logjam
  class LiveStreamPublisher
    def initialize(stream)
      @stream = stream
      @app = stream.app
      @env = stream.env
    end

    def publish(modules, totals_buffer, errors_buffer)
      publish_totals(modules, totals_buffer)
      publish_errors(modules, errors_buffer)
    end

    def self.exchange(app, env)
      (@exchange||={})["#{app}-#{env}"] ||=
        begin
          channel = AMQP::Channel.new(AMQP.connect(:host => live_stream_host))
          channel.auto_recovery = true
          channel.topic("logjam-performance-data-#{app}-#{env}")
        end
    end

    def self.live_stream_host
      @live_stream_host ||= Logjam.streams["livestream-#{Rails.env}"].host
    end

    def exchange
      @exchange ||= self.class.exchange(@app, @env)
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
      exchange.publish(data.to_json, :key => p.sub(/^::/,'').downcase)
    rescue
      $stderr.puts "could not publish performance/error data: #{$!}"
    end
  end

end

require 'amqp'

module Logjam

  class Device
    attr_reader :bindings

    def initialize(streams = nil, options = {})
      @streams = streams || Logjam.streams
      @options = options
      @bindings = get_bindings
    end

    def configure_brokers
      EM.run do
        @bindings.each do |broker, streams|
          environments = streams.map{|s| s.env}.uniq
          configure_broker(broker, environments, streams)
        end
        EM.add_timer(5){ EM.stop }
      end
    end

    def proxy_config
      lines = []
      lines << "ipcdir = \"#{Logjam.ipc_dir}\""
      lines << "backend"
      lines << "    streams"
      proxied_streams.map(&:importer_exchange_name).sort.each do |exchange_name|
        lines << "        #{exchange_name}"
      end
      lines << "frontend"
      lines << "    endpoints"
      get_endpoints.each do |env, hosts|
        lines << "        #{env}"
        hosts.each_with_index do |host, i|
          lines << "            bind#{i+1} = \"tcp://#{host}:9606\""
        end
      end
      lines.join("\n")
    end

    def test_broker(broker, env)
      works = false
      verbose = ENV['VERBOSE'] == "1"
      EM.run do
        AMQP.connect(:host => broker) do |connection|
          AMQP::Channel.new(connection) do |channel|
            device_exchange = declare_device_exchange(broker, channel, env)
            test_queue = channel.queue("logjam-device-test", :auto_delete => true, :exclusive => true)
            test_queue.bind(device_exchange, :routing_key => '#')
            test_queue.subscribe do |meta, payload|
              puts payload if verbose
              works = true
            end
          end
        end
        EM.add_timer(5){ EM.stop }
      end
      puts "logjam device works: #{works}"
      works
    end

    private

    def internal_exchange_name(env=nil)
      # ["logjam-device-internal", env].compact.join('-')
      "logjam-device-internal"
    end

    def importer_streams
      @streams.values.select{|s| s.respond_to?(:importer) }
    end

    def proxied_streams
      importer_streams.select{|s| s.importer.sub_type == :proxy}
    end

    def get_bindings
      importer_streams.each_with_object({}) do |stream, info|
        next unless stream.importer.type == :amqp
        next unless %w(edge preview).include?(stream.env)
        stream.importer.hosts.each do |host|
          (info[host] ||= []) << stream
        end
      end
    end

    def get_endpoints
      proxied_streams.each_with_object({}) do |stream, info|
        env = stream.env
        info[env] = ((info[env]||[]) + stream.importer.hosts).uniq.sort
      end
    end

    def configure_broker(broker, environments, streams)
      AMQP.connect(:host => broker) do |connection|
        AMQP::Channel.new(connection) do |channel|
          internal_exchange_for_env = {}
          environments.each do |env|
            internal_exchange_for_env[env] = declare_device_exchange(broker, channel, env)
          end
          streams.each do |stream|
            device_exchange = internal_exchange_for_env[stream.env]
            declare_and_bind_request_stream(stream, broker, channel, device_exchange)
          end
        end
      end
    end

    def declare_device_exchange(broker, channel, env)
      internal_exchange_name = internal_exchange_name(env)
      puts "declaring device internal exchange #{internal_exchange_name} on #{broker}"
      channel.topic(internal_exchange_name, :durable => true, :auto_delete => false, :internal => true)
    end

    def declare_and_bind_request_stream(stream, broker, channel, device_exchange)
      exchange_name = stream.importer_exchange_name
      puts "declaring request stream exchange #{exchange_name} on #{broker}"
      request_stream_exchange = channel.topic(exchange_name, :durable => true, :auto_delete => false)
      device_exchange.bind(request_stream_exchange, :routing_key => '#')
    end
  end

end

require 'amqp'
require 'date'
require 'json'

module Logjam

  class AMQPImporter

    def initialize(config_name)
      @stream = Logjam.streams[config_name]
      @application = @stream.app
      @environment = @stream.env
      @importer = MongoImporter.new
    end

    def process
      EM.run do
        trap("INT") { EM.stop_event_loop }
        trap("TERM") { EM.stop_event_loop }
        @timer = EM.add_periodic_timer(1) do
          @importer.flush_buffers
        end
        queues.each do |queue|
          queue.subscribe do |header, msg|
            process_request(msg, header.routing_key)
          end
        end
        if queues.empty?
          $stderr.puts "could not connect to any streams. rabbits all down?"
          EM.stop_event_loop
        end
      end
    end

    def stop
      EM.stop_event_loop
      @importer.flush_buffers
    end

    private

    def queues
      @queues ||= @stream.importer.hosts.map{ |host| create_queue host}.compact
    end

    def create_queue(importer_host)
      puts "connecting importer input stream to rabbit on #{importer_host}"
      connection = AMQP::connect(:host => importer_host)
      # TODO: this will likely break with newer version of the AMQP gem
      connection.instance_variable_set("@on_disconnect", proc{ connection.__send__(:reconnect) })
      channel = MQ.new(connection)
      exchange = channel.topic(exchange_name, :durable => true, :auto_delete => false)
      queue = channel.queue(queue_name, :auto_delete => true, :exclusive => true)
      queue.bind(exchange, :routing_key => routing_key)
    rescue Exception => e
      puts "could not connect to rabbit on #{importer_host}"
      nil
    end

    def exchange_name
      [@stream.importer.exchange, @application, @environment].compact.join("-")
    end

    def routing_key
      ["logs", @application, "#"].compact.join('.')
    end

    def queue_name
      [@stream.importer.queue, @application, @environment, `hostname`.chomp].compact.join('-')
    end

    def process_request(msg, routing_key)
      entry = JSON.parse(msg)
      @importer.add_entry entry.merge!(:app => @application, :env => @environment)
    end

  end
end

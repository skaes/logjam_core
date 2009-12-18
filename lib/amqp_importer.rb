require 'amqp'
require 'mq'
require 'date'

class AMQPImporter
  attr_accessor :last_processed_date
  RAILS_ENV = ENV['RAILS_ENV'] || 'development'

  def initialize
    @importer = MysqlImporter.new("/dev/null")
  end

  def process
    EM.run do
      EM.add_periodic_timer(60) do
        import_csv_data
      end
      queue.subscribe do |msg|
        process_line(msg)
      end
    end
  end

  def stop
    AMQP.stop { EM.stop }
    import_csv_data
  end

  private

    def import_csv_data
      @importer.close_csv_files
      @importer.import_csv_files
      @importer.remove_csv_files
    end

    def queue
      @queue ||= begin
        config = load_config('amqp.yml')

        channel = MQ.new(AMQP::connect(:host => config[:hostname]))
        exchange = channel.topic(config[:exchange])
        queue = channel.queue("#{config[:queue]}-#{`hostname`.chomp}", :auto_delete => true, :exclusive => true)

        queue.bind(exchange, :routing_key => "logs.app.*.statistics")
        queue
      end
    end

    def process_line(msg)
      Parser.parse_line(msg) do |entry|
        @importer.add_entry entry.to_hash
      end
    end

    def load_config(config_name)
      YAML.load_file(File.join(File.dirname(__FILE__), '..', 'config', config_name))[RAILS_ENV].symbolize_keys
    end

end

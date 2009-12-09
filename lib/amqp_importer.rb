require 'rubygems'
require 'yaml'
require 'amqp'
require 'mq'
require 'date'
require 'em/mysql'


class AMQPImporter
  attr_accessor :last_processed_date
  RAILS_ENV = ENV['RAILS_ENV'] || 'development'
  SQL = EventedMysql

  def initialize
    setup_mysql
  end

  def process
    EM.run do
      queue.subscribe do |msg|
        process_line(msg)
      end
    end
  end
  
  def stop
    AMQP.stop { EM.stop }
  end

  private
    def queue
      @queue ||= begin
        config = load_config('amqp.yml')

        channel = MQ.new(AMQP::connect(:host => config[:hostname]))
        exchange = channel.topic(config[:exchange])
        queue = channel.queue(config[:queue], :auto_delete => true, :exclusive => true)

        queue.bind(exchange, :routing_key => "logs.app.*.statistics")
        queue
      end
    end

    def process_line(msg)
      Parser.parse_line(msg) do |entry|
        write_to_db_async(entry)
      end
    end

    def ensure_table_exists(current_date_str)
      if current_date_str != self.last_processed_date
        self.last_processed_date = current_date_str
        ControllerAction.ensure_table_exists(current_date_str)
      end
    end

    def write_to_db_async(entry)
      current_date_str = Date.today.to_s
      ensure_table_exists(current_date_str)

      used_values = entry.to_hash.slice(*columns)

      keys    = []
      values  = []

      used_values.each_pair do |key, value|
        keys << key
        values << (value.is_a?(Numeric) ? value : "\'#{value}\'")
      end

      query = "INSERT INTO log_data_#{current_date_str.gsub('-', '_')} (#{keys.join(',')}) VALUES (#{values.join(',')})"
      SQL.insert(query)
    end

    def columns
      @columns ||= ControllerAction.column_names.map(&:to_sym).reject{|c|c==:id}
    end
    
    def setup_mysql
      EventedMysql.settings.update(mysql_config)
    end
    
    def load_config(config_name)
      YAML.load_file(File.join(File.dirname(__FILE__), '..', 'config', config_name))[RAILS_ENV].symbolize_keys
    end

    def mysql_config
      defaults = {
        :host => "localhost",
        :connections => 4
      }

      loaded_config = load_config('database.yml')
      defaults.update(loaded_config.slice(:host, :database))
    end
end

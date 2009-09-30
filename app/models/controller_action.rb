class ControllerAction < ActiveRecord::Base
  class << self

    def date
      nil
    end

    def log_data_table_name(date_str)
      "log_data_#{sanitize_date(date_str)}"
    end
    
    def log_data_tables
      ControllerAction.connection.select_values("show tables").select{|t| t =~ /^log_data_/}
    end

    def log_data_dates
      log_data_tables.map{|t| t.sub('log_data_', '').gsub('_', '-')}.sort.reverse.reject{ |d| ControllerAction[d].first.nil? }
    end

    def drop_data_tables
      ControllerAction.log_data_tables.each do |table_name|
        ActiveRecord::Base.connection.execute "drop table #{table_name}"
      end
    end
    
    def class_for_date(date_str)
      class_name = "ControllerAction_#{sanitize_date(date_str)}"
      table_name = log_data_table_name(date_str)
      unless Object.const_defined?(class_name)
        ensure_table_exists(date_str)
        eval "class ::#{class_name} < ::ControllerAction; def self.date; Time.parse('#{date_str}'); end; def self.table_name; \"#{table_name}\"; end; end"
      end
      Object.const_get class_name
    end
    alias_method :[], :class_for_date
    
    def create_table_sql(date_str)
      "create table if not exists #{log_data_table_name(date_str)} like #{ControllerAction.table_name}"
    end

    def ensure_table_exists(date_str = nil)
      date_str ||= date.to_s(:db)
      connection.execute create_table_sql(date_str)
    end

    def sanitize_date(date_str)
      case date_str
      when Time, Date, DateTime
        date_str = date_str.to_s(:db)
      end
      raise "invalid date" unless date_str =~ /^\d\d\d\d-\d\d-\d\d/
      date_str[0..9].gsub("-", "_")
    end

    def count_distinct_users
      connection.select_value "select count(distinct user_id) from #{table_name}"
    end

    [:host, :page, :response_code].each do |attribute|
      define_method "distinct_#{attribute}s" do
        connection.select_values "SELECT DISTINCT #{attribute} FROM #{table_name} ORDER BY #{attribute} ASC"
      end
    end

    def durations
      ['1', '2', '5']
    end
  end
end

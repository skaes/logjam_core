module Logjam

  Database = Struct.new(:_id, :name, :stream, :date)

  class StreamNotFound < StandardError; end
  class IllegalDatabaseName < StandardError; end

  class Database
    class << self
      def stream_and_date_for(db_name)
        if db_name =~ DB_NAME_FORMAT
          stream = Logjam.streams["#{$1}-#{$2}"]
          if stream
            return stream, $3
          else
            msg = "could not find stream for database: '#{db_name}'"
            Rails.logger.fatal msg
            raise StreamNotFound.new(msg)
          end
        else
          msg = "database name did not match db name format: '#{db_name}'"
          Rails.logger.fatal msg
          raise IllegalDatabaseName.new(msg)
        end
      end

      def from_db_name(db_name)
        stream, date = stream_and_date_for(db_name)
        Database.new(nil, db_name, stream, date)
      end

      def from_stream_and_date(stream, date)
        db_name = Logjam.db_name(date, stream.app, stream.env)
        Database.new(nil, db_name, stream, date)
      end

      def from_record(id, app, env, date)
        stream = Logjam.streams["#{app}-#{env}"]
        db_name = Logjam.db_name(date, app, env)
        Database.new(id, db_name, stream, date)
      end
    end

    def parsed_date
      Date.parse(date)
    end
  end

end

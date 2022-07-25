module Logjam
  module DatabaseManager
    extend self

    def ensure_indexes(options = {})
      Logjam.connections.each do |_, connection|
        options = options.merge(:unique => true)
        c = collection(connection)

        fields = { :env => -1, :app => 1, :date => -1 }
        c.indexes.create_one(fields, options)

        fields = { :env => -1, :date => -1, :app => 1}
        c.indexes.create_one(fields, options)
      end
    end

    def collection(connection)
      Logjam.global_db(connection)["databases"]
    end

    def get_known_databases_with_connections
      Logjam.connections.map do |_, connection|
        rows = []
        ActiveSupport::Notifications.instrument("mongo.logjam", :query => "load database names") do |payload|
          rows = collection(connection).find.to_a
          payload[:rows] = rows.size
        end
        db_hash =rows.each_with_object({}) do |row, hash|
          db = Database.from_record(*row.values_at(*%w(_id app env date)))
          hash[db.name] = db
        end
        [db_hash, connection]
      end
    end

    def update_known_databases
      known_databases = get_known_databases_with_connections
      today = Date.today
      known_databases.each do |db_hash, connection|
        actual_names = connection.database_names
        databases_to_add = []
        while db_name = actual_names.shift
          db = db_hash.delete(db_name)
          if db.nil? && db_name =~ DB_NAME_FORMAT
            begin
              db = Database.from_db_name(db_name)
              databases_to_add << db unless db.parsed_date > today
            rescue StreamNotFound
              # ignore databases without streams
            end
          end
        end
        databases_to_remove = db_hash.values
        bulk_writes = []
        databases_to_remove.each do |db|
          Rails.logger.debug "removing database: #{db.name}"
          bulk_writes << { :delete_one => { :filter => { :_id => db._id } } }
        end
        databases_to_add.each do |db|
          Rails.logger.debug "adding new database: #{db.name}"
          bulk_writes << { :insert_one => {:app => db.stream.app, :env => db.stream.env, :date => db.date} }
        end
        if bulk_writes.present? && !collection(connection).bulk_write(bulk_writes, :ordered => false)
          Rails.logger.fatal "updating known database collection failed"
        end
      end
    end

    def get_known_databases(selector = {}, options = {})
      limit = options[:limit] || 1_000_000
      sort = options[:sort] || {}
      known_databases = []
      Logjam.connections.each do |_, connection|
        rows = []
        ActiveSupport::Notifications.instrument("mongo.logjam", :query => "load database names") do |payload|
          rows = collection(connection).find(selector).sort(sort).limit(limit).to_a
          payload[:rows] = rows.size
        end
        dbs = rows.map{|row| Logjam.db_name_with_iso_date(*(row.values_at(*%w[date app env])))}
        known_databases.concat(dbs)
      end
      known_databases
    end

    def get_cached_databases(selector = {}, options = {})
      if Logjam.perform_caching
        key = "logjam-known-databases-#{selector}-#{options}"
        Rails.cache.fetch(key, expires_in: 5.minutes) do
          get_known_databases(selector, options)
        end
      else
        get_known_databases(selector, options)
      end
    end

    def databases_sorted_by_date(selector = {})
      get_known_databases(selector).sort_by{|db_name| (db_name =~ DB_NAME_FORMAT && "#{$3}-#{$2}-#{$1}")}
    end

    def default_database
      get_cached_databases({}, :limit => 1, :sort => {env: -1, app: 1}).first || Logjam.fallback_database
    end

    def get_known_dates(selector = {}, options = {:sort => {env: -1, :date => -1}})
      limit = options[:limit] || 1_000_000
      sort = options[:sort] || {}
      known_dates = []
      Logjam.connections.each do |_, connection|
        rows = []
        ActiveSupport::Notifications.instrument("mongo.logjam", :query => "load database dates") do |payload|
          c = collection(connection)
          rows = c.find(selector, :projection => {:date => 1}).sort(sort).limit(limit).to_a
          payload[:rows] = rows.size
        end
        dates = rows.map{|row| row["date"]}
        known_dates.concat(dates)
      end
      known_dates.sort
    end

    def get_cached_dates(selector = {})
      if Logjam.perform_caching
        key = "logjam-known-dates-#{selector}"
        Rails.cache.fetch(key, expires_in: 5.minutes) do
          get_known_dates(selector)
        end
      else
        get_known_dates(selector)
      end
    end

  end
end

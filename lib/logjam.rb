require 'mongo'

module Logjam
  extend self

  @@streams = {}
  def self.streams(tag=nil)
    tag.blank? ? @@streams : @@streams.slice(*@@streams.values.select{|v| v.tag == tag}.map(&:name))
  end

  # declare a performance data stream
  def self.stream(name, &block)
    @@streams[name] = Stream.new(name, &block)
  end

  def self.livestream(name, &block)
    @@streams["livestream-#{name}"] = LiveStream.new(name, &block)
  end

  @@base_url = ''
  def self.base_url=(base_url)
    # make sure it starts with a slash and does not end with slash and has no adjacent slashes
    @@base_url = base_url.insert(0,'/').gsub(/\/$/,'').gsub(/\/\//,'/')
  end

  def self.base_url
    @@base_url
  end

  @@import_threshold = 0
  def self.import_threshold=(import_threshold)
    @@import_threshold = import_threshold.to_i
  end

  def self.import_threshold
    @@import_threshold
  end

  @@request_cleaning_threshold = 120
  def self.request_cleaning_threshold=(request_cleaning_threshold)
    @@request_cleaning_threshold = request_cleaning_threshold.to_i
  end

  def self.request_cleaning_threshold
    @@request_cleaning_threshold
  end

  @@database_cleaning_threshold = 365
  def self.database_cleaning_threshold=(database_cleaning_threshold)
    @@database_cleaning_threshold = database_cleaning_threshold.to_i
  end

  def self.database_cleaning_threshold
    @@database_cleaning_threshold
  end

  def mongo
    @mongo_connection ||= begin
      conn = Mongo::Connection.new(database_config['host'])
      if database_config['user'] && database_config['pass']
        conn.db('admin').authenticate(database_config['user'], database_config['pass'])
      end
      conn
    end
  end

  def db(date, app, env)
    name = db_name(date, app, env)
    mongo.db name
  end

  def db_name(date, app, env)
    "logjam-#{app}-#{env}-#{sanitize_date(date)}"
  end

  def db_name_format(options={})
    opts = options.merge(:app => '.+?', :env => '.+?')
    /^logjam-(#{opts[:app]})-(#{opts[:env]})-((.+?)-(.+?)-(.+?))$/
  end

  def db_date(db_name)
    db_name =~ db_name_format && Date.parse($3)
  end

  def grep(databases, options = {})
    databases.grep(db_name_format(options.merge(:app => '.+?', :env => '.+?')))
  end

  def databases
    get_known_databases
  end

  def global_db
    mongo.db "logjam-global"
  end

  def meta_collection
    global_db["metadata"]
  end

  def ensure_known_database(dbname)
    meta_collection.update({:name => 'databases'}, {'$addToSet' => {:value => dbname}}, {:upsert => true, :multi => false})
  end

  def update_known_databases
    names = mongo.database_names
    known_databases = grep(names)
    meta_collection.create_index("name")
    meta_collection.update({:name => 'databases'}, {'$set' => {:value => known_databases}}, {:upsert => true, :multi => false})
    known_databases
  end

  def get_known_databases
    rows = []
    ActiveSupport::Notifications.instrument("mongo.logjam", :query => "load database names") do |payload|
      rows = meta_collection.find({:name => "databases"},{:fields => ["value"]}).to_a
      payload[:rows] = rows.size
    end
    rows.first["value"]
  end

  def sanitize_date(date_str)
    case date_str
    when Time, Date, DateTime
      date_str = date_str.to_s(:db)
    end
    raise "invalid date" unless date_str =~ /^\d\d\d\d-\d\d-\d\d/
    date_str[0..9]
  end

  def durations
    ['1', '2', '5']
  end

  def ensure_indexes
    databases.each do |db_name|
      db = mongo.db(db_name)
      Totals.ensure_indexes(db["totals"])
      Requests.ensure_indexes(db["requests"])
      Minutes.ensure_indexes(db["minutes"])
      Quants.ensure_indexes(db["quants"])
    end
  end

  def remove_old_requests(delay = 60)
    databases.each do |db_name|
      date = db_date(db_name)
      if Date.today - Logjam.request_cleaning_threshold > date
        db = mongo.db(db_name)
        coll = db["requests"]
        if coll.count > 0
          puts "removing old requests: #{db_name}"
          coll.drop
          db.command(:repairDatabase => 1)
          sleep delay
        end
      end
    end
  end

  def drop_old_databases
    dropped = 0
    databases.each do |db_name|
      date = db_date(db_name)
      if Date.today - Logjam.database_cleaning_threshold > date
        puts "removing old database: #{db_name}"
        mongo.drop_database(db_name)
        dropped += 1
      end
    end
    update_known_databases if dropped > 0
  end

  def update_severities
    databases.each do |db_name|
      puts "updating severities: #{db_name}"
      db = mongo.db(db_name)
      Totals.update_severities(db)
    end
  end

  private
  def database_config
    YAML.load_file("#{Rails.root}/config/logjam_database.yml")[Rails.env]
  end
end

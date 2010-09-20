require 'mongo'

module Logjam
  extend self

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

  @@routing_key_matcher = Logjam::Matchers::ROUTING_KEY_MATCHER
  def self.routing_key_matcher=(matcher)
    @@routing_key_matcher = matcher
  end

  def self.routing_key_matcher
    @@routing_key_matcher
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
    mongo.db db_name(date, app, env)
  end

  def db_name(date, app, env)
    "logjam-#{app}-#{env}-#{sanitize_date(date)}"
  end

  def db_name_format(options={})
    opts = options.merge(:app => '.+?', :env => '.+?')
    /^logjam-(#{opts[:app]})-(#{opts[:env]})-((.+?)-(.+?)-(.+?))$/
  end

  def databases(options={})
    mongo.database_names.grep(db_name_format(options.merge(:app => '.+?', :env => '.+?')))
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

  def database_apps
    databases.map{|t| t[db_name_format, 1]}.uniq.sort
  end

  def database_envs(app)
    databases(:app => app).map{|t| t[db_name_format, 2]}.uniq.sort
  end

  def database_days(app, env)
    databases(:app => app, :env => env).map{|t| t[db_name_format, 3]}.uniq.sort.reverse
  end

  def only_one_env?(app)
    database_envs(app).size == 1
  end

  def only_one_app?
    database_apps.size == 1
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

  private
  def database_config
    YAML.load_file("#{RAILS_ROOT}/config/logjam_database.yml")[RAILS_ENV]
  end
end

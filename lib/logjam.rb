require 'mongo'
require 'oj'

Oj.default_options = {:mode => :compat, :time_format => :ruby}

module Logjam
  extend self

  # set this if your rabbitmq brokers have a flaky connection
  @@use_heart_beats = false
  def self.use_heart_beats
    @@use_heart_beats
  end

  def self.use_heart_beats=(use_heart_beats)
    @@use_heart_beats = use_heart_beats
  end

  @@dryrun = false
  def self.dryrun
    @@dryrun
  end

  def self.dryrun=(dry)
    @@dryrun = dry
  end

  # Network interface the various processes bind to. Defaults to
  # "127.0.0.1", to avoid potential security holes. Set it to
  # "0.0.0.0" for multi machine installs behind a firewall.
  @@bind_ip = "127.0.0.1"
  def self.bind_ip
    @@bind_ip
  end

  def self.bind_ip=(ip)
    @@bind_ip = ip
  end

  def self.bind_ip_for_zmq_spec
    @@bind_ip == "0.0.0.0" ? "*" : @@bind_ip
  end

  @@allow_cross_domain_ajax = false
  def self.allow_cross_domain_ajax
    @@allow_cross_domain_ajax
  end

  def self.allow_cross_domain_ajax=(ip)
    @@allow_cross_domain_ajax = ip
  end

  @@ignored_request_uri = nil
  def self.ignored_request_uri
    @@ignored_request_uri
  end

  def self.ignored_request_uri=(uri)
    @@ignored_request_uri = uri
  end

  @@devices = nil
  def self.devices
    @@devices
  end

  def self.devices=(devices)
    @@devices = devices
  end

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

  def self.base_url=(base_url)
    ActiveSupport::Deprecation.warn('Logjam.base_url= is depreated.')
  end

  def self.base_url
    ActiveSupport::Deprecation.warn('Logjam.base_url is depreated.')
    ''
  end

  @@import_threshold = 0
  def self.import_threshold=(import_threshold)
    @@import_threshold = import_threshold.to_i
  end

  def self.import_threshold
    @@import_threshold
  end

  @@import_thresholds = []
  def self.import_thresholds=(import_thresholds)
    @@import_thresholds = import_thresholds
  end

  def self.import_thresholds
    @@import_thresholds
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

  @@database_flush_interval = 1
  def self.database_flush_interval=(database_flush_interval)
    @@database_flush_interval = database_flush_interval.to_i
  end

  def self.database_flush_interval
    @@database_flush_interval
  end

  @@mongo_connections = {}
  def mongo_connection(connection_name)
    config = database_config[connection_name] || database_config['default']
    key = "#{config['host']}-#{config['port']}"
    @@mongo_connections[key] ||=
      begin
        connection = Mongo::Connection.new(config['host'], config['port'])
        if config['user'] && config['pass']
          connection.db('admin').authenticate(config['user'], config['pass'])
        end
        connection
      end
  end

  def establish_connections
    database_config.each_key{|name| mongo_connection(name)}
  end

  def connections
    establish_connections
    @@mongo_connections
  end

  def connection_for(db_name)
    stream = stream_for(db_name)
    mongo_connection(stream.database)
  end

  def db(date, app, env)
    name = db_name(date, app, env)
    connection = connection_for(name)
    connection.db name
  end

  def db_name(date, app, env)
    "logjam-#{app}-#{env}-#{sanitize_date(date)}"
  end

  def db_name_format(options={})
    opts = {:app => '.+?', :env => '.+?'}.merge(options)
    /^logjam-(#{opts[:app]})-(#{opts[:env]})-((.+?)-(.+?)-(.+?))$/
  end

  def db_date(db_name)
    db_name =~ db_name_format && Date.parse($3)
  end

  def extract_db_params(db_name)
    db_name =~ db_name_format && [$1, $2, $3, $4]
  end

  def self.stream_for(db_name)
    db_name =~ db_name_format && @@streams["#{$1}-#{$2}"]
  end

  def iso_date_string(db_name)
    db_name =~ db_name_format && $3
  end

  def grep(databases, options = {})
    opts = {:app => '.+?', :env => '.+?'}.merge(options)
    dbs = databases.grep(db_name_format(opts))
    if date = options[:date]
      dbs.grep(/#{sanitize_date(date)}/)
    else
      dbs
    end
  end

  def databases
    get_known_databases
  end

  def global_db(connection)
    connection.db "logjam-global"
  end

  def meta_collection(connection)
    global_db(connection)["metadata"]
  end

  def ensure_known_database(dbname)
    connection = connection_for(dbname)
    meta_collection(connection).update({:name => 'databases'}, {'$addToSet' => {:value => dbname}}, {:upsert => true, :multi => false})
  end

  def update_known_databases
    all_known_databases = []
    today = Date.today
    connections.each do |_,connection|
      names = connection.database_names
      known_databases = grep(names).reject{|name| db_date(name) > today}.sort
      meta_collection(connection).create_index("name")
      meta_collection(connection).update({:name => 'databases'}, {'$set' => {:value => known_databases}}, {:upsert => true, :multi => false})
      all_known_databases.concat(known_databases)
    end
    if all_known_databases.empty?
      db_name = Logjam.db_name(Date.today, "logjam", Rails.env)
      ensure_known_database(db_name)
      all_known_databases << db_name
    end
    all_known_databases
  end

  def get_known_databases
    all_known_databases = []
    connections.each do |_,connection|
      rows = []
      ActiveSupport::Notifications.instrument("mongo.logjam", :query => "load database names") do |payload|
        rows = meta_collection(connection).find({:name => "databases"},{:fields => ["value"]}).to_a
        payload[:rows] = rows.size
      end
      all_known_databases.concat(rows.first["value"]) unless rows.empty?
    end
    all_known_databases
  end

  def sanitize_date(date_str)
    case date_str
    when Time, Date, DateTime
      date_str = date_str.to_s(:db)
    end
    raise "invalid date: #{date_str.inspect}" unless date_str =~ /^\d\d\d\d-\d\d-\d\d/
    date_str[0..9]
  end

  def durations
    ['1', '2', '5']
  end

  def ensure_indexes
    databases.each do |db_name|
      db = connection_for(db_name).db(db_name)
      Totals.ensure_indexes(db["totals"])
      Requests.ensure_indexes(db["requests"])
      Minutes.ensure_indexes(db["minutes"])
      Quants.ensure_indexes(db["quants"])
    end
  end

  def databases_sorted_by_date
    databases.sort_by{|db| db =~ /^([-a-z]+)-(\d[-0-9]+)/ && "#{$2}-#{$1}"}
  end

  def import_databases(from_host, database_names, options = {})
    options = (options||{}).reverse_merge(:delay => 60, :drop_existing => false)
    puts "importing databases from #{from_host}"
    known_databases = mongo.database_names
    imported = 0
    database_names.each do |db_name|
      if known_databases.include?(db_name)
        if options[:drop_existing]
          puts "dropping target database #{db_name}"
          mongo.drop_database(db_name)
        else
          puts "cowardly refusing to overwrite existing database #{db_name}"
          next
        end
      end
      puts "copying #{db_name} from #{from_host}"
      mongo.copy_database(db_name, db_name, from_host)
      puts "done!"
      imported += 1
      sleep options[:delay]
    end
    if imported > 0
      puts "updating known databases"
      Logjam.update_known_databases
    end
  end

  def remove_old_requests(delay = 60)
    databases_sorted_by_date.each do |db_name|
      date = db_date(db_name)
      stream = stream_for(db_name) || Logjam
      # puts "request cleaning threshold for #{db_name}: #{stream.request_cleaning_threshold}"
      if Date.today - stream.request_cleaning_threshold > date
        begin
          db = connection_for(db_name).db(db_name)
          coll = db["requests"]
          if coll.count > 0
            puts "removing old requests: #{db_name}"
            coll.drop
            begin
              db.command(:repairDatabase => 1)
            rescue => e
              $stderr.puts "#{e.class}(#{e.message})" unless e.message =~ /repairDatabase is a deprecated command/
            end
            sleep delay
          end
        rescue => e
          $stderr.puts "error cleaning requests for: #{db_name}"
          $stderr.puts "#{e.class}(#{e.message})"
        end
      end
    end
  end

  def drop_old_databases(delay = 60)
    dropped = 0
    databases_sorted_by_date.each do |db_name|
      date = db_date(db_name)
      stream = stream_for(db_name) || Logjam
      # puts "db cleaning threshold for #{db_name}: #{stream.database_cleaning_threshold}"
      if Date.today - stream.database_cleaning_threshold > date
        puts "removing old database: #{db_name}"
        connection_for(db_name).drop_database(db_name)
        sleep delay
        dropped += 1
      end
    end
    update_known_databases if dropped > 0
  end

  def drop_empty_databases(app = '.+?', delay = 60)
    dropped = 0
    db_match = db_name_format(:app => app)
    connections.each do |_,connection|
      names = connection.database_names
      names.each do |name|
        next unless name =~ db_match
        db = connection.db(name)
        next unless db.stats["fileSize"] == 0
        puts "dropping empty database: #{name}"
        connection.drop_database(name)
        sleep delay
        dropped += 1
      end
    end
    update_known_databases if dropped > 0
  end

  def drop_all_databases(app = '.+?', delay = 0)
    dropped = 0
    db_match = db_name_format(:app => app)
    connections.each do |_,connection|
      names = connection.database_names
      names.each do |name|
        next unless name =~ db_match
        puts "dropping database: #{name}"
        connection.drop_database(name)
        sleep delay
        dropped += 1
      end
    end
    update_known_databases if dropped > 0
  end

  def drop_applications(apps, delay = 10)
    return if apps.blank?
    dropped = 0
    db_match = db_name_format(:app => apps.join("|"))
    connections.each do |_,connection|
      names = connection.database_names
      names.each do |name|
        next unless name =~ db_match
        puts "dropping database: #{name}"
        connection.drop_database(name)
        sleep delay
        dropped += 1
      end
    end
    update_known_databases if dropped > 0
  end

  def self.drop_frontend_fields_from_db(db)
    counts = %w(frontend_count ajax_count page_count)
    metrics = %w(frontend_time ajax_time page_time load_time processing_time response_time request_time connect_time style_nodes script_nodes html_nodes)
    metrics_sq = metrics.map{|m| "#{m}_sq"}
    fields = counts + metrics + metrics_sq + %w(fapdex papdex xapdex)
    fields = fields.each_with_object({}){|f,h| h[f] = true}
    %w[totals minutes].each do |collection|
      db[collection].update({}, {'$unset' => fields}, :multi => true)
    end
    db["quants"].remove({"kind" => "f"})
  end

  def self.drop_frontend_fields(date, delay=5)
    dbs = grep(databases, :date => date)
    dbs.each do |db_name|
      db = connection_for(db_name).db(db_name)
      puts "dropping frontend fields from #{db_name}"
      drop_frontend_fields_from_db(db)
      sleep delay
    end
  end

  def list_databases_without_requests()
    db_info = []
    databases_sorted_by_date.each do |db_name|
      date = db_date(db_name)
      stream = stream_for(db_name) || Logjam
      # puts "request cleaning threshold for #{db_name}: #{stream.request_cleaning_threshold}"
      if Date.today - stream.request_cleaning_threshold > date
        db_info << "#{database_config[stream.database]['host']}:#{db_name}"
      end
    end
    puts db_info.sort.join("\n")
  end

  def list_all_databases
    db_info = []
    databases_sorted_by_date.each do |db_name|
      stream = stream_for(db_name) || Logjam
      db_info << "#{database_config[stream.database]['host']}:#{db_name}"
    end
    puts db_info.join("\n")
  end

  def update_severities
    databases.each do |db_name|
      puts "updating severities: #{db_name}"
      db = connection_for(db_name).db(db_name)
      Totals.update_severities(db)
    end
  end

  @@database_config ||= {}
  def database_config(env = Rails.env)
    @@database_config[env] ||= YAML.load_file("#{Rails.root}/config/logjam_database.yml")[env]
  end
end

require 'mongo'
require 'oj'

Oj.default_options = {:mode => :custom, :time_format => :ruby, :use_to_hash => true}

module Logjam
  extend self

  # set this to the url under which logjam is reachable
  @@logjam_url = nil
  def self.logjam_url
    @@logjam_url
  end

  def self.logjam_url=(url)
    @@logjam_url= url
  end

  # set this if you forward logjam messages to graylog
  @@graylog_base_urls = {}
  def self.graylog_base_urls
    @@graylog_base_urls
  end

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

  @@statsd_endpoint = nil
  # either udp://host:port or tcp://host:port
  def self.statsd_endpoint=(spec)
    @@statsd_endpoint = spec
  end

  def self.statsd_endpoint
    @@statsd_endpoint
  end

  @@statsd_namespace = "logjam"
  def self.statsd_namespace=(namespace)
    @@statsd_namespace = namespace
  end

  def self.statsd_namespace
    @@statsd_namespace
  end

  @@importer_subscriber_threads = 1
  def self.importer_subscriber_threads
    @@importer_subscriber_threads
  end

  def self.importer_subscriber_threads=(n)
    @@importer_subscriber_threads = n
  end

  @@importer_parser_threads = 8
  def self.importer_parser_threads
    @@importer_parser_threads
  end

  def self.importer_parser_threads=(n)
    @@importer_parser_threads = n
  end

  @@importer_updater_threads = 10
  def self.importer_updater_threads
    @@importer_updater_threads
  end

  def self.importer_updater_threads=(n)
    @@importer_updater_threads = n
  end

  @@importer_writer_threads = 10
  def self.importer_writer_threads
    @@importer_writer_threads
  end

  def self.importer_writer_threads=(n)
    @@importer_writer_threads = n
  end

  @@importer_io_threads = 1
  def self.importer_io_threads
    @@importer_io_threads
  end

  def self.importer_io_threads=(n)
    @@importer_io_threads = n
  end

  @@frontend_timings_collector = nil
  def self.frontend_timings_collector=(spec)
    spec[-1] = "" if spec && spec[-1] == "/"
    @@frontend_timings_collector = spec
  end

  def self.frontend_timings_collector
    @@frontend_timings_collector
  end

  @@frontend_timings_collector_port = 9705
  def self.frontend_timings_collector_port=(port)
    if (p = port.to_i) > 0
      @@frontend_timings_collector_port = p
    end
  end

  def self.frontend_timings_collector_port
    @@frontend_timings_collector_port
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

  def self.default_web_socket_uri(request)
   "#{web_socket_protocol}://#{request.host}:#{web_socket_port}/"
  end

  @@web_socket_uri = nil
  def self.web_socket_uri(request)
    @@web_socket_uri || default_web_socket_uri(request)
  end

  def self.web_socket_uri=(uri)
    @@web_socket_uri = uri
  end

  @@web_socket_protocol = "ws"
  def self.web_socket_protocol
    @@web_socket_protocol
  end

  def self.web_socket_protocol=(protocol)
    @@web_socket_protocol = protocol
  end

  @@web_socket_port = RUBY_PLATFORM =~ /darwin/ ? 9608 : 8080
  def self.web_socket_port
    @@web_socket_port
  end

  def self.web_socket_port=(port)
    @@web_socket_port = port
  end

  @@backend_only_requests = ""
  def self.backend_only_requests
    @@backend_only_requests
  end

  def self.backend_only_requests=(prefixes)
    @@backend_only_requests = prefixes
  end

  @@sampling_rate_400s = 1
  def self.sampling_rate_400s
    @@sampling_rate_400s
  end

  def self.sampling_rate_400s=(r)
    @@sampling_rate_400s = r
  end

  @@http_buckets = [0.001, 0.0025, 0.005, 0.010, 0.025, 0.050, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 25, 50, 100]
  def self.http_buckets
    @@http_buckets
  end

  def self.http_buckets=(r)
    @@http_buckets = r
  end

  @@jobs_buckets = [0.001, 0.0025, 0.005, 0.010, 0.025, 0.050, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 25, 50, 100]
  def self.jobs_buckets
    @@jobs_buckets
  end

  def self.jobs_buckets=(r)
    @@jobs_buckets = r
  end

  @@page_buckets = [0.005, 0.010, 0.025, 0.050, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 25, 50, 100, 250]
  def self.page_buckets
    @@page_buckets
  end

  def self.page_buckets=(r)
    @@page_buckets = r
  end

  @@ajax_buckets = [0.005, 0.010, 0.025, 0.050, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 25, 50, 100, 250]
  def self.ajax_buckets
    @@ajax_buckets
  end

  def self.ajax_buckets=(r)
    @@ajax_buckets = r
  end

  @@github_issue_url = "https://github.com/skaes/logjam_app/issues/new"
  def self.github_issue_url
    @@github_issue_url
  end

  def self.github_issue_url=(r)
    @@github_issue_url = r
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

  def self.production_streams
    streams.reject{|name,stream| stream.is_a?(LiveStream) || stream.env == "development"}
  end

  # declare a performance data stream
  def self.stream(name, &block)
    @@streams[name] = Stream.new(name, &block)
  end

  def self.livestream(name, &block)
    @@streams["livestream-#{name}"] = LiveStream.new(name, &block)
  end

  # regexp matcher for application names
  @@app_regex = nil
  def self.app_regex
    @@app_regex ||=
      begin
        applications = production_streams.map{|name, stream| stream.app}.uniq
        /\A(#{applications.join('|')})-(.*)\z/
      end
  end

  # extract app from a app-action pair
  def self.extract_app(pair)
    if pair =~ app_regex
      [$1, $2]
    else
      pair.split('-', 2)
    end
  end

  def self.base_url=(base_url)
    ActiveSupport::Deprecation.warn('Logjam.base_url= is depreated.')
  end

  def self.base_url
    ActiveSupport::Deprecation.warn('Logjam.base_url is depreated.')
    ''
  end

  @@max_inserts_per_second = 100
  def self.max_inserts_per_second=(max_inserts_per_second)
    @@max_inserts_per_second = max_inserts_per_second.to_i
  end

  def self.max_inserts_per_second
    @@max_inserts_per_second
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
        connection_spec = "#{config['host']}:#{config['port']}"
        options = { :connect_timeout => 60, :socket_timeout => 60 }
        if config['user'] && config['pass']
          options.merge!(:user => config['user'], :password => config['pass'])
        end
        Mongo::Client.new([connection_spec], options)
      end
  rescue
    Rails.logger.error("could not establish connection for '#{connection_name}'")
    raise
  end

  def establish_connections
    database_config.each_key{|name| mongo_connection(name)}
  end

  def connections
    establish_connections
    @@mongo_connections
  end

  # retrieving a connection this way only works if the stream still exists
  # this causes problems when trying to delete databaes of removed apps
  def connection_for(db_name)
    stream = stream_for(db_name)
    Rails.logger.debug "trying to connect db for stream #{stream.inspect}"
    mongo_connection(stream.database)
  end

  def db(date, app, env)
    name = db_name(date, app, env)
    connection = connection_for(name)
    connection.use(name).database
  end

  def db_name(date, app, env)
    "logjam-#{app}-#{env}-#{sanitize_date(date)}"
  end

  DB_NAME_FORMAT = /\Alogjam-(.+)-([^-]+)-((\d+?)-(\d+?)-(\d+?))\z/
  # $1 => app, $2 => env, $3 => date

  def db_name_format(options={})
    if options.blank?
      DB_NAME_FORMAT
    else
      opts = {:app => '.+', :env => '[^-]+'}.merge(options)
      /\Alogjam-(#{opts[:app]})-(#{opts[:env]})-((\d+?)-(\d+?)-(\d+?))\z/
    end
  end

  def db_date(db_name)
    db_name =~ DB_NAME_FORMAT && Date.parse($3)
  end

  def extract_db_params(db_name)
    db_name =~ DB_NAME_FORMAT && [$1, $2, $3]
  end

  def app_for(db_name)
    db_name =~ DB_NAME_FORMAT && $1
  end

  def self.stream_defined?(app, env)
    @@streams["#{app}-#{env}"]
  end

  def self.stream_for(db_name)
    if db_name =~ DB_NAME_FORMAT
      stream = @@streams["#{$1}-#{$2}"]
      if stream
        stream
      else
        msg = "could not find stream for database: '#{db_name}'"
        Rails.logger.fatal msg
        raise msg
      end
    else
      msg = "database name did not match db name format: '#{db_name}'"
      Rails.logger.fatal msg
      raise msg
    end
  end

  def iso_date_string(db_name)
    db_name =~ DB_NAME_FORMAT && $3
  end

  def grep(databases, options = {})
    opts = {:app => '.+', :env => '[^-]+'}.merge(options)
    dbs = databases.grep(db_name_format(opts))
    if date = options[:date]
      dbs.grep(/#{sanitize_date(date)}/)
    else
      dbs
    end
  end

  def databases
    if perform_caching
      Rails.cache.fetch("logjam-known-databases", expires_in: 5.minutes) do
        get_known_databases
      end
    else
      get_known_databases
    end
  end

  def global_db(connection)
    connection.use "logjam-global"
  end

  def meta_collection(connection)
    global_db(connection)["metadata"]
  end

  def ensure_known_database(dbname)
    connection = connection_for(dbname)
    meta_collection(connection).find(:name => 'databases').update_one({'$addToSet' => {:value => dbname}}, :upsert => true)
  end

  def update_known_databases
    all_known_databases = []
    today = Date.today
    connections.each do |_,connection|
      names = connection.database_names
      known_databases = grep(names).reject{|name| db_date(name) > today}.sort
      meta_collection(connection).indexes.create_one(name: 1)
      meta_collection(connection).find(:name => 'databases').update_one({'$set' => {:value => known_databases}}, :upsert => true)
      all_known_databases.concat(known_databases)
    end
    if all_known_databases.empty?
      db_name = Logjam.db_name(Date.today, "logjam", Rails.env)
      ensure_known_database(db_name)
      all_known_databases << db_name
    end
    all_known_databases
  end

  def get_known_databases_with_connections
    known_databases_with_connections = []
    connections.each do |_,connection|
      rows = []
      ActiveSupport::Notifications.instrument("mongo.logjam", :query => "load database names") do |payload|
        rows = meta_collection(connection).find(:name => "databases").projection(value: 1).to_a
        payload[:rows] = rows.size
      end
      unless rows.empty?
        pairs = rows.first["value"].map{|db_name| [db_name, connection]}
        known_databases_with_connections.concat(pairs)
      end
    end
    known_databases_with_connections
  end

  def get_known_databases
    get_known_databases_with_connections.map(&:first)
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

  def request_collection_expired?(db_name)
    date = db_date(db_name)
    stream = stream_for(db_name) || Logjam
    Date.today - stream.request_cleaning_threshold > date
  end

  def index_with_mongo_rescue(collection_name)
    yield
  rescue => e
    puts "could not index #{collection_name}: #{e}"
  end

  def ensure_indexes(options = {})
    failures = []
    databases_sorted_by_date.each do |db_name|
      begin
        puts "#{db_name}: reindexing"
        db = connection_for(db_name).use(db_name).database
        index_with_mongo_rescue("totals") do
          Totals.ensure_indexes(db["totals"], options)
        end
        index_with_mongo_rescue("minutes") do
          Minutes.ensure_indexes(db["minutes"], options)
        end
        index_with_mongo_rescue("quants") do
          Quants.ensure_indexes(db["quants"], options)
        end
        if request_collection_expired?(db_name)
          puts "not creating indexes for expired requests collection "
        else
          index_with_mongo_rescue("requests") do
            Requests.ensure_indexes(db["requests"], options)
          end
        end
      rescue => e
        puts "unexpected failure: #{e}"
        failures << db_name
      end
    end
    unless failures.empty?
      puts "the following databases could not be indexed:"
      puts failures.sort.join("\n")
    end
  end

  def databases_sorted_by_date
    get_known_databases.sort_by{|db| (db =~ DB_NAME_FORMAT && "#{$3}-#{$2}-#{$1}")}
  end

  def databases_sorted_by_date_with_connections
    get_known_databases_with_connections.sort_by{|db, _| db =~ DB_NAME_FORMAT && "#{$3}-#{$2}-#{$1}"}
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
          mongo.use(db_name).database.drop
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
    databases_sorted_by_date_with_connections.each do |db_name, connection|
      begin
        if request_collection_expired?(db_name)
          db = connection.use(db_name).database
          collection_names = db.collection_names
          %w(requests metrics).each do |collection_name|
            next unless collection_names.include?(collection_name)
            puts "removing collection #{collection_name} from #{db_name}"
            db[collection_name].drop
            sleep delay
          end
        end
      rescue => e
        $stderr.puts "error cleaning requests for: #{db_name}"
        $stderr.puts "#{e.class}(#{e.message})"
      end
    end
  end

  def drop_old_databases(delay = 60)
    dropped = 0
    databases_sorted_by_date_with_connections.each do |db_name, connection|
      begin
        date = db_date(db_name)
        stream = stream_for(db_name) || Logjam
        # puts "db cleaning threshold for #{db_name}: #{stream.database_cleaning_threshold}"
        if Date.today - stream.database_cleaning_threshold > date
          puts "removing old database: #{db_name}"
          begin
            connection.use(db_name).database.drop
          rescue => e
            puts e.message
          end
          sleep delay
          dropped += 1
        end
      rescue => e
        $stderr.puts "error dropping old database: #{db_name}"
        $stderr.puts "#{e.class}(#{e.message})"
      end
    end
    update_known_databases if dropped > 0
  end

  def list_empty_databases
    empty = []
    get_known_databases_with_connections.each do |db_name, connection|
      db = connection.use(db_name).database
      stats = db.command(:dbStats => 1).first
      next unless stats.present? && (stats[:objects] || stats["objects"]) == 0
      empty << db_name
    end
    empty.sort.join("\n")
  end

  def list_object_counts
    object_count = Hash.new(0)
    get_known_databases_with_connections.each do |db_name, connection|
      db = connection.use(db_name).database
      stats = db.command(:dbStats => 1).first
      next unless stats.present?
      count = stats["objects"].to_i
      stream = stream_for(db_name)
      object_count[stream.name] += count
    end
    object_count.to_a.sort_by{|n,c| [c,n]}.map{|n,c| "#{n}:#{c}"}.join("\n")
  end

  def drop_empty_databases(app = '.+', delay = 60)
    dropped = 0
    db_match = db_name_format(:app => app)
    connections.each do |_,connection|
      names = connection.database_names
      names.each do |name|
        next unless name =~ db_match
        db = connection.use(name).database
        stats = db.command(:dbStats => 1).first
        next unless stats.present? && (stats[:objects] || stats["objects"]) == 0
        puts "dropping empty database: #{name}"
        connection.use(name).database.drop
        sleep delay
        dropped += 1
      end
    end
    update_known_databases if dropped > 0
  end

  def drop_all_databases(app: '.+', env: '[^-]+' , delay: 0)
    dropped = 0
    db_match = db_name_format(:app => app, :env => env)
    connections.each do |_,connection|
      names = connection.database_names
      names.each do |name|
        next unless name =~ db_match
        puts "dropping database: #{name}"
        connection.use(name).database.drop
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
        connection.use(name).database.drop
        sleep delay
        dropped += 1
      end
    end
    update_known_databases if dropped > 0
  end

  def drop_environments(envs, delay = 10)
    return if envs.blank?
    dropped = 0
    db_match = db_name_format(:env => envs.join("|"))
    connections.each do |_,connection|
      names = connection.database_names
      names.each do |name|
        next unless name =~ db_match
        puts "dropping database: #{name}"
        connection.use(name).database.drop
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
      db[collection].update_many('$unset' => fields)
    end
    db["quants"].remove({"kind" => "f"})
  end

  def self.drop_frontend_fields(date, delay=5)
    dbs = grep(databases, :date => date)
    dbs.each do |db_name|
      db = connection_for(db_name).use(db_name).database
      puts "dropping frontend fields from #{db_name}"
      drop_frontend_fields_from_db(db)
      sleep delay
    end
  end

  def self.drop_histograms(from_date, to_date, delay=5)
    for date in from_date..to_date
      dbs = grep(databases, :date => date)
      dbs.each do |db_name|
        db = connection_for(db_name).use(db_name).database
        next unless db.collection_names.include?("histograms")
        puts "dropping histograms collection from #{db_name}"
        db["histograms"].drop
        sleep delay
      end
    end
  end

  def self.drop_metrics(from_date, to_date, delay=5)
    require 'byebug'
    for date in from_date..to_date
      dbs = grep(databases, :date => date)
      dbs.each do |db_name|
        db = connection_for(db_name).use(db_name).database
        next unless db.collection_names.include?("metrics")
        puts "dropping metrics collection from #{db_name}"
        db["metrics"].drop
        sleep delay
      end
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
      db = connection_for(db_name).use(db_name).database
      Totals.update_severities(db)
    end
  end

  def merge_database(date:, app:, env:, other_db:, other_app:, merge_requests: false, merge_stats: true)
    db = db(date, app, env)
    source_db_name = db_name(date, other_app || app, env)
    if other_db.present?
      source_db = Mongo::Client.new([other_db], {:connect_timeout => 60, :socket_timeout => 60 }).use(source_db_name).database
    elsif other_app.blank?
      raise ArgumentError.new("merging dbs on same mongo connection requires two different applications")
    else
      source_db = db(date, other_app, env)
    end
    if merge_stats
      MongoModel.merge_stats(db, source_db, "totals", %w(_id page))
      MongoModel.merge_stats(db, source_db, "minutes", %w(_id page minute))
      MongoModel.merge_stats(db, source_db, "quants", %w(_id kind page quant))
      MongoModel.merge_stats(db, source_db, "heatmaps", %w(_id page minute))
      MongoModel.merge_stats(db, source_db, "agents", %w(_id agent))
      MongoModel.merge_collection(db, source_db, "events", use_id: false)
      MongoModel.merge_collection(db, source_db, "js_exceptions", use_id: false)
    end
    if merge_requests
      MongoModel.merge_collection(db, source_db, "requests", use_id: true)
      MongoModel.merge_collection(db, source_db, "metrics", use_id: true)
    end
  end

  def merge_databases(date:, other_db:, other_app:)
    dbs = grep(databases, :date => date)
    dbs.each do |db_name|
      puts "merging #{db_name}"
      app, env = extract_db_params(db_name)
      merge_database(date: date, app: app, env: env, other_db: other_db, other_app: other_app)
    end
  end

  def rename_callers_and_senders(date:, from_app:, to_app:)
    dbs = grep(databases, :date => date)
    dbs.each do |db_name|
      puts "renaming callers and senders in #{db_name}"
      app, env = extract_db_params(db_name)
      next if app == from_app
      db = db(date, app, env)
      MongoModel.rename_callers_and_senders(db, "totals", from_app, to_app)
      MongoModel.rename_callers_and_senders(db, "minutes", from_app, to_app)
    end
  end

  @@database_config ||= {}
  def database_config(env = Rails.env)
    @@database_config[env] ||=
      begin
        file_name = "#{Rails.root}/config/logjam_database.yml"
        file_contents = ERB.new(File.read(file_name)).result
        YAML.load(file_contents)[env]
      end
  end

  def database_keys
    @database_keys ||= %w[default] + (database_config.keys - %w[default])
  end

  def database_number(db_name)
    database_keys.index(db_name)
  end

  def user_agents
    user_agents = Agents.create_stats_hash
    databases_sorted_by_date_with_connections.each do |db_name, connection|
      date = db_date(db_name)
      if date > Date.today - 14
        db = connection.use(db_name).database
        agent_infos = Agents.new(db).find(select: Agents::BACKEND)
        agent_infos.each do |a|
          user_agents[a.agent].merge!(a)
        end
      end
    end
    user_agents.values.sort_by{|a| -a.backend}
  end

  def list_action_names(from_date:, to_date:)
    names = Set.new
    databases_sorted_by_date_with_connections.each do |db_name, connection|
      date = db_date(db_name)
      next if date < from_date || date > to_date
      db = connection.use(db_name).database
      pages = Totals.new(db).page_names
      names.merge(pages)
    end
    names.to_a.sort_by{|s|s}.each do |n|
      puts n
    end
  end

  def list_action_name_characters(from_date:, to_date:)
    used_characters_by_app = Hash.new{|h,k| h[k] = Set.new}
    databases_sorted_by_date_with_connections.each do |db_name, connection|
      date = db_date(db_name)
      next if date < from_date || date > to_date
      unless app = app_for(db_name)
        $stderr.puts("could not extract app from databse name: #{db_name}")
        app = "unknown"
      end
      db = connection.use(db_name).database
      pages = Totals.new(db).page_names
      pages.each do |page|
        page.chars.each do |s|
          used_characters_by_app[s] << app
        end
      end
    end
    used_characters = used_characters_by_app.keys.sort_by{|s|s}
    used = used_characters.join
    asciis = (32..127).map(&:chr).to_set
    remmaining_ascii_codes = (asciis - used_characters.to_set).to_a.sort_by{|s|s}
    remaining = remmaining_ascii_codes.join
    puts "used characters:#{used}"
    puts "remaining chars:#{remaining}"
    puts "apps using special characters"
    normal_chars = (("0".."9").to_a + ("A".."Z").to_a + ("a".."z").to_a).join + "_:#"
    used_characters.each do |c|
      next if normal_chars.include?(c)
      apps = used_characters_by_app[c].to_a.sort_by{|s|s}
      puts "#{c} #{apps.join(" ")}"
    end
  end

  # don't use memcache if environment variable LOGJAM_USE_CACHE is '0'
  def perform_caching
    (ENV['LOGJAM_USE_CACHE'] ||= '1') != '0'
  end

  def get_collection_info(db)
    db.collection_names.sort.map do |c|
      [c, db.command(collstats: c).first.slice(:count, :size, :storageSize, :totalIndexSize, :avgObjSize).symbolize_keys]
    end
  end

  def get_cached_database_info
    get_info = -> (*_args) {
      info = []
      connections.each do |host, conn|
        conn.list_databases.each do |db_hash|
          db_name = db_hash["name"]
          db_size = db_hash["sizeOnDisk"]
          info << [host, db_name, db_size]
        end
      end
      info
    }
    if perform_caching
      Rails.cache.fetch("logjam-database-info", expires_in: 5.minutes, &get_info)
    else
      get_info.call
    end
  end

end

require "rake/testtask"

namespace :test do
  Rake::TestTask.new(:logjam) do |t|
    t.warning = false
    t.libs << "test"
    t.pattern = 'vendor/logjam/test/**/*_test.rb'
  end
end

# run logjam core tests as part of app tests
Rake::Task['test'].enhance ['test:logjam']

namespace :logjam do

  def app_dir
    Rails.root.to_s
  end

  def logjam_dir
    "#{app_dir}/vendor/logjam"
  end

  namespace :db do
    desc "ensure indexes"
    task :reindex => :environment do
      Logjam.ensure_indexes
    end

    desc "drop old databases DELAY=5"
    task :drop_old => :environment do
      delay = (ENV['DELAY'] || 5).to_i
      Logjam.drop_old_databases(delay)
    end

    desc "drop empty databases APPLICATION=regexp DELAY=5"
    task :drop_empty => :environment do
      delay = (ENV['DELAY'] || 5).to_i
      app = ENV['APPLICATION'] || '.+?'
      Logjam.drop_empty_databases(app, delay)
    end

    desc "drop applications APPLICATIONS=a,b,c DELAY=5"
    task :drop_apps => :environment do
      delay = (ENV['DELAY'] || 5).to_i
      Logjam.drop_applications(ENV['APPLICATIONS'].to_s.split(/\s*,\s*/), delay)
    end

    desc "drop environments ENVS=a,b,c DELAY=5"
    task :drop_envs => :environment do
      delay = (ENV['DELAY'] || 5).to_i
      Logjam.drop_environments(ENV['ENVS'].to_s.split(/\s*,\s*/), delay)
    end

    desc "remove frontend fields from all dbs DATE=yesterday DELAY=5"
    task :drop_frontend_fields => :environment do
      delay = (ENV['DELAY'] || 5).to_i
      date = (ENV['DATE'] || Date.today-1).to_date
      Logjam.drop_frontend_fields(date, delay)
    end

    desc "drop old histogram collections"
    task :drop_old_histograms => :environment do
      delay = (ENV['DELAY'] || 5).to_i
      from_date = (ENV['FROM_DATE'] || Date.today-1).to_date
      to_date = (ENV['TO_DATE'] || Date.today-1).to_date
      Logjam.drop_histograms(from_date, to_date, delay)
    end

    desc "drop all databases"
    task :drop_all_databases => :environment do
      puts "are you sure to drop all databases from #{Logjam.connections.keys.join(', ')}?"
      print "type YES to proceed: "
      if STDIN.gets.chomp == "YES"
        puts "destruction initiated"
        Logjam.drop_all_databases
      else
        puts "destruction aborted!"
      end
    end

    desc "drop metrics collection"
    task :drop_metrics => :environment do
      delay = (ENV['DELAY'] || 5).to_i
      from_date = (ENV['FROM_DATE'] || Date.today-1).to_date
      to_date = (ENV['TO_DATE'] || Date.today-1).to_date
      Logjam.drop_metrics(from_date, to_date, delay)
    end

    desc "remove old data DELAY=5"
    task :clean => :drop_old do
      delay = (ENV['DELAY'] || 5).to_i
      Logjam.remove_old_requests(delay)
    end

    desc "update severities"
    task :update_severities => :environment do
      Logjam.update_severities
    end

    desc "update known databases"
    task :update_known_databases => :environment do
      Logjam.update_known_databases
    end

    desc "list known databases"
    task :list_known_databases => :environment do
      puts Logjam.databases_sorted_by_date
    end

    desc "import databases"
    task :import_databases => :environment do
      from_host = ENV['FROM_HOST']
      from_file = ENV['FROM_FILE']
      delay = (ENV['DELAY'] || 60).to_i
      drop_existing = ENV['DROP_DB'] == "1"
      if from_host.blank?
        $stderr.puts "no host specified to copy database from. please specify FROM_HOST=..."
        exit 1
      elsif from_file.blank? || ! File.exists?(from_file) || ! File.readable?(from_file)
        $stderr.puts "no file given or not readable. use FROM_FILE=..."
        exit 1
      else
        databases_to_copy = File.readlines(from_file).map(&:strip).map(&:chomp).sort
        Logjam.import_databases(from_host, databases_to_copy, delay: delay, drop_existing: drop_existing)
      end
    end

    desc "merge database DATE= APP= ENV= OTHER_DB=<connection spec, optional>, OTHER_APP=<optional> MERGE_REQUESTS=0|1"
    task :merge_database => :environment do
      date = (ENV['DATE'] || Date.today).to_date
      app = ENV['APP']
      env = ENV['ENV']
      other_db = ENV['OTHER_DB']
      other_app = ENV['OTHER_APP']
      merge_requests = ENV['MERGE_REQUESTS'] == "1"
      Logjam.merge_database(date: date, app: app, env: env, other_db: other_db, other_app: other_app, merge_requests: merge_requests)
    end

    desc "merge requests DATE= APP= ENV= OTHER_DB=<connection spec, optional>, OTHER_APP=<optional>"
    task :merge_requests => :environment do
      date = (ENV['DATE'] || Date.today).to_date
      app = ENV['APP']
      env = ENV['ENV']
      other_db = ENV['OTHER_DB']
      other_app = ENV['OTHER_APP']
      Logjam.merge_database(date: date, app: app, env: env, other_db: other_db, other_app: other_app, merge_requests: true, merge_stats: false)
    end

    desc "merge databases DATE=<today> OTHER_DB=<connection spec>"
    task :merge_databases => :environment do
      date = (ENV['DATE'] || Date.today).to_date
      other_db = ENV['OTHER_DB']
      Logjam.merge_databases(date: date, other_db: other_db)
    end

    desc "rename caller and sender references from FROM_APP to TO_APP between FROM_DATE an TO_DATE"
    task :rename_caller_and_sender_references => :environment do
      from_date = (ENV['FROM_DATE'] || Date.today).to_date
      to_date = (ENV['TO_DATE'] || Date.today).to_date
      from_app = ENV['FROM_APP']
      to_app = ENV['TO_APP']
      (from_date..to_date).each do |date|
        Logjam.rename_callers_and_senders(date: date, from_app: from_app, to_app: to_app)
      end
    end

    desc "list all stored user agents strings"
    task :user_agents => :environment do
      agents = Logjam.user_agents
      Logjam::Agents.dump_array(agents)
    end

    desc "list all action names in all applications between FROM_DATE an TO_DATE"
    task :list_action_names => :environment do
      from_date = (ENV['FROM_DATE'] || Date.today).to_date
      to_date = (ENV['TO_DATE'] || Date.today).to_date
      Logjam.list_action_names(from_date: from_date, to_date: to_date)
    end

    desc "list all characters used in action names in all applications between FROM_DATE an TO_DATE"
    task :list_action_name_characters => :environment do
      from_date = (ENV['FROM_DATE'] || Date.today).to_date
      to_date = (ENV['TO_DATE'] || Date.today).to_date
      Logjam.list_action_name_characters(from_date: from_date, to_date: to_date)
    end
  end

  namespace :device do
    desc "configure logjam device"
    task :configure => :environment do
      Logjam::Device.new.configure_brokers
    end

    desc "test logjam device config"
    task :test => :environment do
      Logjam::Device.new.test(ENV['LOGJAM_DEVICE_TEST_BROKER'], ENV['LOGJAM_DEVICE_TEST_ENV'])
    end
  end

  namespace :importer do
    namespace :config do
      desc "generate C importer config"
      task :generate => :environment do
        puts Logjam::Importer.new.config
      end
    end
  end

  namespace :daemons do
    def service_dir
      ENV['LOGJAM_SERVICE_DIR'] || "#{app_dir}/service"
    end

    def template_dir
      "#{logjam_dir}/services"
    end

    def service_paths
      Dir["#{service_dir}/*"]
    end

    def services
      service_paths.join(' ')
    end

    def importer_specs
      YAML.load_file("#{ENV['LOGJAM_DIR'] || app_dir}/config/logjam_amqp.yml")
    end

    def clean_path(paths)
      paths.map{|p| p.gsub(/\/+/,'/')}.uniq.join(':')
    end

    def install_service(template_name, service_name, substitutions={})
      target_dir = "#{service_dir}/#{service_name}"
      source_dir = "#{template_dir}/#{template_name}"
      substitutions.merge!(:LOGJAM_DIR => ENV['LOGJAM_DIR'] || app_dir,
                           :LOGJAM_SERVICE_TARGET_DIR => target_dir,
                           :LOGJAM_URL => Logjam.logjam_url,
                           :RAILSENV => ENV['RAILS_ENV'] || "development",
                           :GEMHOME => Gem.dir,
                           :GEMPATH => clean_path((Gem.path+Gem.default_path).uniq),
                           :DAEMON_PATH => clean_path(ENV['PATH'].split(':')))
      FileUtils.mkdir_p("#{target_dir}/log/logs")
      if File.directory?("#{source_dir}/log/logs") && File.exist?("#{source_dir}/log/logs/config")
        FileUtils.cp("#{source_dir}/log/logs/config", "#{target_dir}/log/logs/config")
      else
        FileUtils.rm_f("#{target_dir}/log/logs/config")
      end
      if File.directory?("#{source_dir}/log/errors") && File.exist?("#{source_dir}/log/errors/config")
        FileUtils.mkdir_p("#{target_dir}/log/errors")
        FileUtils.cp("#{source_dir}/log/errors/config", "#{target_dir}/log/errors/config")
      else
        FileUtils.rm_f("#{target_dir}/log/errors")
      end
      # write config file first
      if config = substitutions.delete(:config)
        File.write("#{target_dir}/#{service_name}.conf", config)
      end
      # order is important here: always create the dependent log service first!
      scripts = %w(log/run run)
      scripts.each do |script|
        template = File.read("#{source_dir}/#{script}")
        substitutions.each do |k,v|
          template.gsub!(%r[#{k}], v)
        end
        File.open("#{target_dir}/#{script}", "w"){|f| f.puts template}
        FileUtils.chmod(0755, "#{target_dir}/#{script}")
      end
      service_name
    end

    desc "Install logjam daemons"
    task :install => :environment do
      require "fileutils"
      system("mkdir -p #{service_dir}")
      installed_services = []

      streams = Logjam.streams(ENV['LOGJAM_SERVICE_TAG'])
      streams.each do |i, s|
        next if Rails.env.production? && s.env == 'development'
        if s.is_a?(Logjam::LiveStream) && ENV['LOGJAM_LIVESTREAM_INSTALL'] != '0'
          installed_services <<
            install_service("livestream", "live-stream",
                            :ANOMALIES_HOST => s.anomalies_host,
                            :BIND_IP => Logjam.bind_ip)
        end
      end

      unless ENV['LOGJAM_IMPORTER_INSTALL'] == '0'
        config = Logjam::Importer.new.config
        installed_services << install_service("importer", "importer", :config => config)
      end

      unless ENV['LOGJAM_HTTPD_INSTALL'] == '0'
        collector_port = Logjam.frontend_timings_collector_port
        installed_services << install_service("httpd", "httpd", :HTTPD_PORT => collector_port.to_s)
      end

      old_services = service_paths.map{|f| f.split("/").compact.last} - installed_services
      old_services.each do |old_service|
        puts "removing old service #{old_service}"
        system("rm -rf #{service_dir}/#{old_service}")
      end
    end

    desc "Start logjam daemons"
    task :start do
      system("sv up #{services}")
    end

    desc "Stop logjam daemons"
    task :stop do
      system("sv down #{services}")
    end

    desc "Show logjam daemons status"
    task :status do
      system("sv status #{services}")
    end

    desc "Restart logjam daemons DELAY=1"
    task :restart do
      interrupted=false
      trap('INT'){interrupted=true}
      daemon_match = ENV['DAEMON_MATCH'] ? %r(#{ENV['DAEMON_MATCH']}) : /./
      service_paths.each do |service|
        next unless service =~ daemon_match
        system("sv force-restart #{service}")
        sleep((ENV['DELAY']||1).to_i)
        break if interrupted
      end
    end

    def fetch_orphans
      procs = []
      `ps axo ppid,pid,args | egrep -e logjam-[iwd]`.each_line do |line|
        next if line =~ /runsvdir/
        items = line.chomp.strip.split(/\s+/, 3)
        ppid, pid, cmd = items[0].to_i, items[1].to_i, items[2]
        procs << [pid, cmd] if ppid == 1
      end
      procs
    end

    desc "List orphaned processes"
    task :list_orphans do
      unless (orphans = fetch_orphans).empty?
        sleep 15
        orphans &= fetch_orphans
        host = `hostname`.chomp
        orphans.each do |pid, cmd|
          $stderr.puts "orphan: #{host} #{pid} #{cmd}"
        end
      end
    end
  end

end

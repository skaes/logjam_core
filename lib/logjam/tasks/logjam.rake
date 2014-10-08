namespace :test do
  Rake::TestTask.new(:logjam) do |t|
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

    desc "drop old databases"
    task :drop_old => :environment do
      delay = [ENV['REPAIR_DELAY'].to_i, 5].max
      Logjam.drop_old_databases(delay)
    end

    desc "drop empty databases"
    task :drop_empty => :environment do
      delay = [ENV['REPAIR_DELAY'].to_i, 5].max
      app = ENV['APPLICATION'] || '.+?'
      Logjam.drop_empty_databases(app, delay)
    end

    desc "drop applications APPLICATIONS=a,b,c"
    task :drop_apps => :environment do
      delay = [ENV['REPAIR_DELAY'].to_i, 5].max
      Logjam.drop_applications(ENV['APPLICATIONS'].to_s.split(/\s*,\s*/), delay)
    end

    desc "reomve frontend fields from all dbs DATE=yesterday DROP_DELAY=5"
    task :drop_frontend_fields => :environment do
      delay = (ENV['DROP_DELAY'] || 5).to_i
      date = (ENV['DATE'] || Date.today-1).to_date
      Logjam.drop_frontend_fields(date, delay)
    end

    desc "drop all databases"
    task :drop_all_databases => :environment do
      puts "are you sure to drop all databases from #{Logjam.connections.keys.join(', ')}?"
      print "type YES to proceed: "
      if STDIN.gets.chomp == "YES"
        puts "destruction initiated"
        Logjam.drop_all_databases
      else
        puts "aborted!"
      end
    end

    desc "remove old data"
    task :clean => :drop_old do
      delay = [ENV['REPAIR_DELAY'].to_i, 5].max
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
      puts Logjam.get_known_databases
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

  namespace :cimporter do
    namespace :config do
      desc "generate C importer config"
      task :generate => :environment do
        Logjam::Cimporter.new.generate_config
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
      device = Logjam::Device.new(streams)
      install_c_importer = false
      streams.each do |i, s|
        next if ENV['RAILS_ENV'] == 'production' && s.env == 'development'
        if s.is_a?(Logjam::LiveStream)
          installed_services << install_service("livestream", "live-stream-#{s.env}",
                                                :ANOMALIES_HOST => s.anomalies_host,
                                                :BIND_IP => Logjam.bind_ip)
        elsif s.importer.devices.blank?
          installed_services << install_service("importer", "importer-#{i}", :IMPORTER => i)
        else
          install_c_importer = true
        end
      end
      if install_c_importer
        Logjam::Cimporter.new.generate_config(StringIO.new(config = ""))
        installed_services << install_service("cimporter", "cimporter", :config => config)
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

    desc "Restart logjam daemons"
    task :restart do
      interrupted=false
      trap('INT'){interrupted=true}
      daemon_match = ENV['DAEMON_MATCH'] ? %r(#{ENV['DAEMON_MATCH']}) : /./
      service_paths.each do |service|
        next unless service =~ daemon_match
        system("sv force-restart #{service}")
        sleep((ENV['RESTART_DELAY']||1).to_i)
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

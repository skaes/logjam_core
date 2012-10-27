namespace :logjam do

  def app_dir
    Rails.root.to_s
  end

  def public_dir
    "#{Rails.root}/public"
  end

  def logjam_dir
    "#{Rails.root}/vendor/logjam"
  end

  namespace :assets do
    desc "create symbolic links for logjam assets in the public directory"
    task :link do
      system("find #{public_dir} -type l | xargs rm")

      images = Dir.glob("#{logjam_dir}/assets/images/*.{jpg,png,gif}")
      FileUtils.ln_s images, "#{public_dir}/images/"

      javascripts = Dir.glob("#{logjam_dir}/assets/javascripts/*.js")
      FileUtils.ln_s javascripts, "#{public_dir}/javascripts/"

      stylesheets = Dir.glob("#{logjam_dir}/assets/stylesheets/*.css")
      FileUtils.ln_s stylesheets, "#{public_dir}/stylesheets/"

      FileUtils.ln_s "#{logjam_dir}/assets/stylesheets/smoothness", "#{public_dir}/stylesheets/"

      FileUtils.ln_s "#{logjam_dir}/assets/js", public_dir
    end
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
      substitutions.merge!(:LOGJAM_DIR => ENV['LOGJAM_DIR'] || app_dir,
                           :RAILSENV => ENV['RAILS_ENV'] || "development",
                           :GEMHOME => Gem.dir,
                           :GEMPATH => clean_path((Gem.path+Gem.default_path).uniq),
                           :DAEMON_PATH => clean_path(ENV['PATH'].split(':')))
      system("mkdir -p #{target_dir}/log/logs")
      # order is important here: always create the dependent log service first!
      scripts = %w(log/run run)
      scripts.each do |script|
        template = File.read("#{template_dir}/#{template_name}/#{script}")
        substitutions.each do |k,v|
          template.gsub!(%r[#{k}], v)
        end
        File.open("#{target_dir}/#{script}", "w"){|f| f.puts template}
        system("chmod 755 #{target_dir}/#{script}")
      end
      service_name
    end

    desc "Install logjam daemons"
    task :install => :environment do
      system("mkdir -p #{service_dir}")
      installed_services = []
      Logjam.streams(ENV['LOGJAM_SERVICE_TAG']).each do |i, s|
        next if ENV['RAILS_ENV'] == 'production' && s.env == 'development'
        if s.is_a?(Logjam::LiveStream)
          installed_services << install_service("livestream", "live-stream-#{s.env}", :LIVE_STREAM_BROKER => s.host)
        else
          installed_services << install_service("importer", "importer-#{i}", :IMPORTER => i)
        end
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
    task :restart => [:stop, :start]

  end

end

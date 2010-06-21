# Be sure to restart your server when you modify this file

# Specifies gem version of Rails to use when vendor/rails is not present
RAILS_GEM_VERSION = '2.3.4' unless defined? RAILS_GEM_VERSION

# Bootstrap the Rails environment, frameworks, and default configuration
require File.join(File.dirname(__FILE__), 'boot')

Rails::Initializer.run do |config|
  config.action_controller.session_store = :nil_session_store

  # Settings in config/environments/* take precedence over those specified here.
  # Application configuration should go into files in config/initializers
  # -- all .rb files in that directory are automatically loaded.

  # Add additional load paths for your own custom dirs
  # config.load_paths += %W( #{RAILS_ROOT}/extras )

  # use built-in csv with ruby 1.9, and fastercsv with 1.8
  if RUBY_VERSION > "1.9"
    config.gem 'mysql'
    require "csv"
    ::FasterCSV = CSV unless defined? FasterCSV
  else
    config.gem 'fastercsv', :source => 'http://gems.rubyforge.org'
    require "fastercsv"
  end

  config.gem 'mongo'

  # Specify gems that this application depends on and have them installed with rake gems:install
  # config.gem "bj"
  # config.gem "hpricot", :version => '0.6', :source => "http://code.whytheluckystiff.net"
  # config.gem "sqlite3-ruby", :lib => "sqlite3"
  # config.gem "aws-s3", :lib => "aws/s3"
  config.gem 'logjam_logger', :version => '1.1.0'
  config.gem 'gnuplot', :source => 'http://gems.rubyforge.org'
  config.gem 'memcached' unless defined? JRUBY_VERSION

  # Only load the plugins named here, in the order given (default is alphabetical).
  # :all can be used as a placeholder for all plugins not explicitly named
  # config.plugins = [ :exception_notification, :ssl_requirement, :all ]

  # Skip frameworks you're not going to use. To use Rails without a database,
  # you must remove the Active Record framework.
  # config.frameworks -= [ :active_record, :active_resource, :action_mailer ]

  # Activate observers that should always be running
  # config.active_record.observers = :cacher, :garbage_collector, :forum_observer

  # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
  # Run "rake -D time" for a list of tasks for finding time zone names.
  config.time_zone = 'UTC'

  # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
  # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}')]
  # config.i18n.default_locale = :de

  config.after_initialize do
    require 'digest/md5'

    ActiveSupport::Dependencies.load_once_paths.reject! { |p| p =~ %r{/lib/} }
  end

  if GC.respond_to?(:log_file)
    config.to_prepare do
      # toggle GC tracing on signal USR1
      trap('USR1') do
        file = File.expand_path(File.dirname(__FILE__)+"/../log/gc-#{$$}.log")
        GC.log_file file unless GC.log_file
        if GC.enable_stats # were stats already enabled?
          GC.disable_trace
          GC.disable_stats
          RAILS_DEFAULT_LOGGER.info 'GC-tracing: enabled'
        else
          GC.enable_trace
          RAILS_DEFAULT_LOGGER.info 'GC-tracing: disabled'
        end
      end
    end
  end
end


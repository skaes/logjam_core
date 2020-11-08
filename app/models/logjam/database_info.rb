module Logjam
  # stores database info as two level hash { app => { env => [day1, day2, ...]}}
  class DatabaseInfo

    attr_reader :databases, :exception

    def valid?
      !@exception
    end

    def initialize(date = nil)
      today = Date.today
      date ||= today
      @info = {}
      envs = Set.new
      @exception = nil
      @databases = []
      begin
        @databases = Logjam.databases
      rescue Exception => @exception
        Rails.logger.error("#{@exception.class}(#{@exception})")
      end
      streams = Logjam.production_streams.values
      @databases.concat(streams.map{|s| Logjam.db_name(date, s.app, s.env) })
      @databases.concat(streams.map{|s| Logjam.db_name(today, s.app, s.env) }) if date != today
      @databases.uniq!
      @databases.map! do |db_name|
        if db_name =~ Logjam::DB_NAME_FORMAT && Logjam.stream_defined?($1, $2)
          envs << $2
          ((@info[$1] ||= {})[$2] ||= []) << $3
        else
          nil
        end
      end
      @databases.compact!
      @databases.sort!
      @all_envs = envs.to_a.sort.reverse
    end

    def apps
      @apps ||= @info.keys.sort
    end

    def apps_for_env(env)
      @apps_for_env ||= @info.select{|app,envs| envs.include?(env)}.keys
    end

    def all_envs
      @all_envs
    end

    def envs(app)
      @info[app].keys.sort.reverse rescue []
    end

    def days(app, env)
      @info[app][env].sort.reverse rescue []
    end

    def only_one_env?(app = nil)
      (@info[app] || @all_envs).size == 1
    end

    def only_one_app?
      @info.size == 1
    end

    def default_app
      apps.first
    end

    def default_env(app)
      envs(app).select{|e| e=="production"}.first || envs(app).first || "production"
    end

    def db_exists?(date, app, env)
      @info[app][env].include?(Logjam.sanitize_date(date)) rescue false
    end

    def to_hash
      info = @databases.map{|s| s =~ NAME_FORMAT && {:app => $1, :env => $2, :date => $3}}.compact
      { :databases => info }
    end
  end
end

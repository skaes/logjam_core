module Logjam
  # stores database info as two level hash { app => { env => [day1, day2, ...]}}
  class DatabaseInfo

    NAME_FORMAT = Logjam.db_name_format
    attr_reader :databases

    def initialize
      @databases = Logjam.databases
      @databases << Logjam.db_name(Date.today, "logjam", Rails.env) if @databases.empty?
      @info = {}
      @databases.each do |dbname|
        if dbname =~ NAME_FORMAT
          app, env, date = $1, $2, $3
          ((@info[app] ||= {})[env] ||= []) << date
        end
      end
    end

    def apps
      @apps ||= @info.keys.sort
    end

    def apps_for_env(env)
      @apps_for_env ||= @info.select{|app,envs| envs.include?(env)}.keys
    end

    def envs(app)
      @info[app].keys.sort.reverse rescue []
    end

    def days(app, env)
      @info[app][env].sort.reverse rescue []
    end

    def only_one_env?(app)
      @info[app].size == 1 rescue false
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

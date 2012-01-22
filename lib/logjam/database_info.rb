module Logjam
  # stores database info as two level hash { app => { env => [day1, day2, ...]}}
  class DatabaseInfo

    NAME_FORMAT = Logjam.db_name_format
    attr_reader :databases

    def initialize
      @databases = Logjam.databases
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

    def envs(app)
      @info[app].keys.sort.reverse
    end

    def days(app, env)
      @info[app][env].sort.reverse
    end

    def only_one_env?(app)
      @info[app].size == 1
    end

    def only_one_app?
      @info.size == 1
    end

    def default_app
      apps.first
    end

    def default_env(app)
      envs(app).select{|e| e=="production"}.first || envs.first
    end

    def db_exists?(date, app, env)
      ((@info[app]||{})[env]||[]).include?(date)
    end
  end
end

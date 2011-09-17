module Logjam
  class DatabaseInfo

    NAME_FORMAT = Logjam.db_name_format

    def databases
      @databases ||= Logjam.databases
    end

    def apps
      databases.map{|t| t[NAME_FORMAT, 1]}.uniq.sort
    end

    def envs(app)
      Logjam.grep(databases, :app => app).map{|t| t[NAME_FORMAT, 2]}.uniq.sort
    end

    def days(app, env)
      Logjam.grep(databases, :app => app, :env => env).map{|t| t[NAME_FORMAT, 3]}.uniq.sort.reverse
    end

    def only_one_env?(app)
      envs(app).size == 1
    end

    def only_one_app?
      apps.size == 1
    end

    def default_app
      apps.first
    end

    def default_env(app)
      envs(app).select{|e| e=="production"}.first || envs.first
    end

  end
end

module Logjam
  module MongoTimeConsumer
    extend self

    def info
      Thread.current[:mongo_database_info] ||= [0.0, 0]
    end

    def info=(info)
      Thread.current[:mongo_database_info] = info
    end

    def reset
      reset_stats
      self.info = [0.0, 0]
    end

    def consumed
      time, calls = reset_stats
      i = self.info
      i[1] += calls
      i[0] += time
    end

    def runtime
      time, calls = *info
      sprintf "Mongo: %.3fms(%d)", time*1000, calls
    end

    def metrics
      {
        :db_time => info[0]*1000,
        :db_calls => info[1],
      }
    end

    private

    def reset_stats
      s = MongoLogSubscriber
      calls = s.reset_call_count
      time  = s.reset_runtime
      [time.to_f/1000, calls]
    end
  end
end

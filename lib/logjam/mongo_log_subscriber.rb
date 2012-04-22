module Logjam
  class MongoLogSubscriber < ActiveSupport::LogSubscriber
    @@mongo_runtime = 0.0
    def self.runtime=(value)
      @@mongo_runtime = value
    end

    def self.runtime
      @@mongo_runtime ||= 0
    end

    def self.reset_runtime
      rt, @@mongo_runtime = @@mongo_runtime, 0
      rt
    end

    @@mongo_calls = 0
    def self.call_count
      @@mongo_calls
    end

    def self.reset_call_count
      cc, @@mongo_calls = @@mongo_calls, 0
      cc
    end

    def mongo(event)
      @@mongo_runtime += event.duration
      @@mongo_calls += 1

      return unless logger.debug?

      debug 'MONGO %s returned %d rows (%.1fms)' % [event.payload[:query], event.payload[:rows], event.duration]
    end
  end
end

Logjam::MongoLogSubscriber.attach_to :logjam

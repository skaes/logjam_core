module Logjam
  class LogSubscriber < ActiveSupport::LogSubscriber
    def self.runtime=(value)
      Thread.current["mongo_runtime"] = value
    end

    def self.runtime
      Thread.current["mongo_runtime"] ||= 0
    end

    def self.reset_runtime
      rt, self.runtime = runtime, 0
      rt
    end

    def mongo(event)
      self.class.runtime += event.duration
      return unless logger.debug?

      debug 'MONGO %s returned %d rows (%.1fms)' % [event.payload[:query], event.payload[:rows], event.duration]
    end
  end
end

Logjam::LogSubscriber.attach_to :logjam

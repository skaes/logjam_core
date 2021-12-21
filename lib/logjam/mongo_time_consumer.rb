module Logjam
  class MongoTimeConsumer < TimeBandits::TimeConsumers::BaseConsumer
    prefix :db
    fields :time, :calls
    format  "Mongo: %.3fms(%d)", :time, :calls

    class Subscriber < ActiveSupport::LogSubscriber
      def mongo(event)
        i = MongoTimeConsumer.instance
        i.time += event.duration
        i.calls += 1

        return unless logger.debug?

        p = event.payload
        debug "MONGO %s returned %d rows (%.1fms)" % [p[:query], p[:rows] || 0, event.duration]
      end
      Subscriber.attach_to :logjam
    end
  end
end

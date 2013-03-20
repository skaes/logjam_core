module Logjam
  class Events

    include Helpers

    def initialize(db)
      @database   = db
      @collection = db.collection("events")
    end

    def insert(event)
      @collection.insert(event.merge(:minute => extract_minute_from_iso8601(event["started_at"])))
    end

    def events
      @events ||= compute
    end

    private

    def db
      Logjam.db
    end

    def compute
      rows = []
      selector = ["minute", "label"]
      query = "#{self.class}.find.each"
      ActiveSupport::Notifications.instrument("mongo.logjam", :query => query) do |payload|
        @collection.find.each do |row|
          rows << row
        end
        payload[:rows] = rows.size
      end
      rows
    end

  end
end

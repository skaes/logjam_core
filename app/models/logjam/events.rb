module Logjam
  class Events < MongoModel

    include Helpers

    def initialize(db)
      super(db, "events")
    end

    def insert(event)
      @collection.insert(event.merge(:minute => extract_minute_from_iso8601(event["started_at"])))
    end

    def events
      @events ||= compute
    end

    private

    def compute
      query = "#{self.class}.find.each"
      with_conditional_caching(query) do |payload|
        rows = []
        @collection.find.each do |row|
          row.delete("_id")
          rows << row
        end
        payload[:rows] = rows.size
        rows
      end
    end

  end
end

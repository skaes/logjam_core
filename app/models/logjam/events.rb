module Logjam
  class Events

    include Helpers

    attr_accessor :events

    def initialize(db)
      @database = db
      @collection = @database["events"]
      @events = compute
    end

    def self.insert(event)
      @collection.insert({:minute => extract_minute_from_iso8601(event["started_at"]), :label => event["label"]})
    end

    private

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
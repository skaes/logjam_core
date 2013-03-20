module Logjam
  class Events

    include Helpers

    def self.ensure_indexes(collection)
      ms = Benchmark.ms do
        collection.create_index([ ["page", Mongo::ASCENDING], ["minute", Mongo::ASCENDING] ], :background => true)
      end
      logger.debug "MONGO #{self.class} Indexes Creation: #{"%.1f" % (ms)} ms"
      collection
    end

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
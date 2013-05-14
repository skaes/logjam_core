module Logjam
  class JsExceptions

    include Helpers

    def self.request_id_from_exception(exception)
      exception["request_id"] = exception["logjam_request_id"].split('-').last
    end

    def initialize(db)
      @database   = db
      @collection = db.collection("js_exceptions")
      @collection.ensure_index('logjam_request_id')
    end

    def all
      @collection.find.to_a
    end

    def find_by_request(request_id)
      @collection.find('logjam_request_id' => request_id)
    end

    def insert(exception)
      @collection.insert(exception.merge(:minute => extract_minute_from_iso8601(exception["started_at"])))
    end

    def exceptions
      @exceptions ||= compute
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

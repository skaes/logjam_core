module Logjam
  class JsExceptions

    include Helpers

    def self.request_id_from_exception(exception)
      exception["request_id"] = exception["logjam_request_id"].split('-').last
    end

    def self.key_from_description(description)
      key = URI.escape(description, /[.$]/)
    end

    def self.description_from_key(mongo_key)
      key = URI.unescape(mongo_key)
    end

    def initialize(db)
      @database   = db
      @collection = db.collection("js_exceptions")
      @collection.ensure_index('logjam_request_id')
      @collection.ensure_index('description')
    end

    def all
      @collection.find.to_a
    end

    def count(options = {})
      @collection.find(options[:selector]).count()
    end

    def find(options = {})
      selector = options.delete(:selector)
      @collection.find(selector, options).to_a
    end

    def find_by_request(request_id)
      @collection.find('logjam_request_id' => request_id).to_a
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

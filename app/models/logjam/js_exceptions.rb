module Logjam
  class JsExceptions < MongoModel

    include Helpers

    def self.request_id_from_exception(exception)
      exception["request_id"] = exception["logjam_request_id"].split('-').last
    end

    def self.key_from_description(description)
      URI.escape(description, /[.$]/).force_encoding('UTF-8')
    end

    def self.description_from_key(mongo_key)
      URI.unescape(mongo_key)
    end

    def initialize(db)
      super(db, "js_exceptions")
      @collection.indexes.create_one(logjam_request_id: 1)
      @collection.indexes.create_one(description: 1)
    end

    def all
      get_rows
    end

    def count(options = {})
      selector = options[:selector]
      with_conditional_caching("JsExceptions.count(#{selector})") do |payload|
        payload[:rows] = 1
        @collection.find(selector).count()
      end
    end

    def find(options = {})
      selector = options.delete(:selector)
      get_rows(selector, options)
    end

    def find_by_request(request_id)
      get_rows({'logjam_request_id' => request_id})
    end

    def insert(exception)
      @collection.insert(exception.merge(:minute => extract_minute_from_iso8601(exception["started_at"])))
    end

    def exceptions
      @exceptions ||= get_rows
    end

    private

    def get_rows(selector, options={})
      query, log = build_query("JsExceptions.get_rows", selector, options)
      with_conditional_caching(log) do |payload|
        rows = []
        query.each do |row|
          if (id = row["_id"]) && id.is_a?(BSON::Binary)
            row["_id"] = id.data.to_s
          end
          rows << row
        end
        payload[:rows] = rows.size
        rows
      end
    end
  end
end

module Logjam

  class MongoModel
    def initialize(db, collection_name)
      @database = db
      @perform_caching = Logjam.db_date(@database.name) < Date.today
      @collection = db.collection(collection_name)
    end

    def logger; Rails.logger; end
    def self.logger; Rails.logger; end

    private

    def instrument(query, &block)
      ActiveSupport::Notifications.instrument("mongo.logjam", :query => query, &block)
    end

    def with_conditional_caching(query, &block)
      if @perform_caching
        key = "#{@database.name}-#{query}"
        Rails.cache.fetch(key) do
          instrument(query, &block)
        end
      else
        instrument(query, &block)
      end
    end

  end
end

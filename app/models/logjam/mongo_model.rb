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
        key = cache_key(query)
        Rails.cache.fetch(key) do
          instrument(query, &block)
        end
      else
        instrument(query, &block)
      end
    end

    if Rails.env.production?
      def cache_key(query)
        "#{@database.name}-#{query}"
      end
    else
      def cache_key(query)
        "#{Rails.env}-#{@database.name}-#{query}"
      end
    end

    def _fields(array)
      Hash[* array.flat_map{ |x| [x,1] }]
    end

    def build_query(name, selector, opts = {})
      query = @collection.find(selector)
      log = "#{name}(#{selector.inspect})"

      if projection = opts[:projection]
        query = query.projection(projection)
        log << ".projection(#{projection})"
      end

      if sort = opts[:sort]
        query = query.sort(sort)
        log << ".sort(#{sort})"
      end

      if limit = opts[:limit]
        query = query.limit(limit)
        log << ".limit(#{limit})"
      end

      if skip = opts[:skip]
        query = query.skip(skip)
        log << ".skip(#{skip})"
      end

      [query, log]
    end

  end
end

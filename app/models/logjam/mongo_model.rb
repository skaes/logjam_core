module Logjam

  class MongoModel
    def initialize(db, collection_name)
      @database = db
      @perform_caching = Logjam.db_date(@database.name) < Date.today && Logjam.perform_caching
      @collection = db.collection(collection_name)
    end

    def logger; Rails.logger; end
    def self.logger; Rails.logger; end

    def self.convert_pair(key, val)
      case val
      when Float, Integer
        { key => val }
      when Hash
        val.each_with_object({}) do |(k,v), h|
          h.merge!(convert_pair("#{key}.#{k}", v))
        end
      else
        raise "unexpected value for key #{key}: #{v.class}(#{v.inspect})"
      end
    end

    def self.to_upsert(hash, keys: %w(_id page))
      selector = hash.slice(*keys).except("_id")

      flat_hash = {}
      hash.except(*keys).each do |k,v|
        flat_hash.merge!( convert_pair(k,v) )
      end
      incs = flat_hash.select{|k,_| k !~ /_max\z/}
      maxs = flat_hash.select{|k,_| k =~ /_max\z/}
      {:selector => selector, :incs => incs, :maxs => maxs}
    end

    def self.merge_stats(db, source_db, collection_name, keys)
      collection = db.collection(collection_name)
      source_collection = source_db.collection(collection_name)
      source_collection.find.each do |row|
        params = to_upsert(row, keys: keys)
        operation = { '$inc' => params[:incs] }
        operation.merge!('$max' => params[:maxs]) unless params[:maxs].empty?
        begin
          collection.update_one(params[:selector], operation, :upsert => true)
        rescue => e
          puts "collection #{collection_name}: update failed: #{e}"
        end
      end
    end

    def self.merge_collection(db, source_db, collection_name, use_id: true)
      collection = db.collection(collection_name)
      source_collection = source_db.collection(collection_name)
      source_collection.find.each do |row|
        begin
          row.delete("_id") unless use_id
          collection.insert_one(row)
        rescue => e
          puts "collection #{collection_name}: insert failed: #{e}"
        end
      end
    end

    def self.rename_callers_and_senders(db, collection_name, from_app, to_app)
      collection = db.collection(collection_name)
      selector = {'$or' => [ { 'callers' => {'$exists' => 1} }, { 'senders' => {'$exists' => 1} }]}
      bulk_writes = []
      collection.find(selector, :projection => {'callers' => 1,  'senders' => 1}).each do |row|
        deletions = {}
        increments = {}
        (row['callers']||[]).each do |kaller, count|
          if kaller =~ /\A#{from_app}([@-])(.*)\z/
            deletions["callers.#{kaller}"] = 1
            increments["callers.#{to_app}#{$1}#{$2}"] = count
          end
        end
        (row['senders']||[]).each do |sender, count|
          if sender =~ /\A#{from_app}([@-])(.*)\z/
            deletions["senders.#{sender}"] = 1
            increments["senders.#{to_app}#{$1}#{$2}"] = count
          end
        end
        next if increments.empty?
        bulk_writes << {
          :update_one => {
            :filter => { '_id' => row['_id'] },
            :update => { '$inc' => increments, '$unset' => deletions }
          }}
      end
      return false if bulk_writes.empty?
      begin
        if collection.bulk_write(bulk_writes, :ordered => false)
          return true
        else
          puts "collection #{collection_name}: update failed: #{e}"
        end
      rescue => e
        puts "collection #{collection_name}: update failed: #{e}"
      end
      return false
    end

    def database_storage_size
      instrument("#{@database.name}.storage_size") do |payload|
        payload[:rows] = 1
        @database.command(:dbStats => 1, :scale => 1_073_741_824).first["storageSize"]
      end
    end

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
      log = "#{name}(#{selector.to_json})"

      if projection = opts[:projection]
        query = query.projection(projection)
        log << ".projection(#{projection.to_json})"
      end

      if sort = opts[:sort]
        query = query.sort(sort)
        log << ".sort(#{sort.to_json})"
      end

      if limit = opts[:limit]
        query = query.limit(limit)
        log << ".limit(#{limit.to_json})"
      end

      if skip = opts[:skip]
        query = query.skip(skip)
        log << ".skip(#{skip.to_json})"
      end

      [query, log]
    end

    def collection_names
      @database.collection_names
    end
  end
end

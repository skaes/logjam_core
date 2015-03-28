module Logjam

  class Agents < MongoModel
    def initialize(db)
      super(db, "agents")
    end

    def all
      selector = {}
      query_opts = {:fields => [:agent, :backend, :frontend]}
      query = "Agents.find(#{selector.inspect},#{query_opts.inspect})"
      rows = with_conditional_caching(query) do |payload|
        # explain = @collection.find(selector, query_opts.dup).explain
        # logger.debug explain.inspect
        rs = []
        @collection.find(selector, query_opts).each do |row|
          row.delete("_id")
          rs << row
        end
        payload[:rows] = rs.size
        rs
      end
      rows
    end

    def count
      selector = {}
      query = "Agents.count(#{selector.inspect})"
      with_conditional_caching(query) do |payload|
        payload[:rows] = 1
        @collection.find(selector).count
      end
    end
  end

end

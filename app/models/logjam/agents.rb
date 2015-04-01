module Logjam

  class Agents < MongoModel
    def initialize(db)
      super(db, "agents")
    end

    def find(limit: nil)
      selector = {}
      query_opts = {:fields => [:agent, :backend, :frontend], :sort => [:backend, -1]}
      query_opts.merge!(limit: limit) if limit
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

    def summary
      group = { _id: nil, count:  {:$sum => 1}, backend: {:$sum => '$backend'}, frontend: {:$sum => '$frontend'}}
      pipeline = [{'$group' => group }]
      query = "Agents.aggregate(#{pipeline.inspect})"
      with_conditional_caching(query) do |payload|
        payload[:rows] = 1
        @collection.aggregate(pipeline).first || empty_summary
      end
    end

    private
    def empty_summary
      {"count" => 0, "backend" => 0, "frontend" => 0}
    end
  end

end

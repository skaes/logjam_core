module Logjam

  class Agents < MongoModel

    AgentInfo = Struct.new(:agent, :backend, :frontend, :dropped)
    class AgentInfo
      class << self
        def member_names
          @member_names ||= members.map(&:to_s)
        end

        def from_hash(h)
          new(*h.values_at(*member_names))
        end
      end

      def member_names
        self.class.member_names
      end

      # for Oj
      alias_method :to_hash, :to_h

      def merge!(other)
        self.backend  += other.backend  || 0
        self.frontend += other.frontend || 0
        self.dropped  += other.dropped  || 0
      end
    end

    def self.create_stats_hash
      Hash.new { |h,k| h[k] = AgentInfo.new(k,0,0,0) }
    end

    def self.array_to_csv(agents, header: true)
      str = CSV.generate(:col_sep => ';') do |csv|
        csv << %w(Backend-Count Frontend-Count Dropped User-Agent) if header
        agents.each do |a|
          csv << [a.backend, a.frontend, a.dropped, a.agent,]
        end
      end
      str
    end

    def self.dump_array(agents, out = $stdout)
      agents.each do |a|
        out.puts [a.backend, a.frontend, a.dropped, a.agent].join(':')
      end
    end

    ALL      = {}
    BACKEND  = { backend:  {:$gt => 0} }
    FRONTEND = { frontend: {:$gt => 0} }

    def initialize(db)
      super(db, "agents")
    end

    def agent_names(select: ALL)
      query = "Agents.distinct(:agent,#{select.inspect})"
      with_conditional_caching(query) do |payload|
        rows = @collection.distinct(:agent, select)
        payload[:rows] = rows.size
        rows
      end
    end

    def find(limit: nil, select: ALL)
      query_opts = { :projection => { agent: 1, backend: 1, frontend: 1, dropped: 1 } }
      query_opts.merge!(limit: limit) if limit
      query, log = build_query("Agents.find", select, query_opts)
      rows = with_conditional_caching(log) do |payload|
        rs = []
        query.each do |row|
          agent = AgentInfo.from_hash(row)
          rs << agent
        end
        payload[:rows] = rs.size
        rs
      end
      rows.sort_by{|a| -a.backend}
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
      group = {
        _id: nil,
        count:      { :$sum => 1 },
        backend:    { :$sum => '$backend' },
        frontend:   { :$sum => '$frontend' },
        dropped:    { :$sum => '$dropped' },
        outlier:    { :$sum => '$drop_reasons.outlier' },
        nav_timing: { :$sum => '$drop_reasons.nav_timing' },
        illegal:    { :$sum => '$drop_reasons.illegal' },
        corrupted:  { :$sum => '$drop_reasons.corrupted' },
        invalid:    { :$sum => '$drop_reasons.invalid' },
      }
      pipeline = [{:$group => group }]
      query = "Agents.aggregate(#{pipeline.inspect})"
      with_conditional_caching(query) do |payload|
        payload[:rows] = 1
        @collection.find.aggregate(pipeline).first.try(&:symbolize_keys) || empty_summary
      end
    end

    private
    def empty_summary
      {
        count: 0, backend: 0, frontend: 0, dropped: 0, outlier: 0,
        nav_timing: 0, illegal: 0, corrupted: 0, invalid: 0
      }
    end
  end

end

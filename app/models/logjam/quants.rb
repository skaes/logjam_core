module Logjam

  class Quants < MongoModel

    def self.ensure_indexes(collection, options = {})
      ms = Benchmark.ms do
        fields = { "page" => 1, "kind" => 1, "quant" => 1 }
        collection.indexes.create_one(fields, options)
      end
      logger.debug "MONGO Quants Indexes Creation: #{"%.1f" % (ms)} ms"
      collection
    end

    def initialize(db, resources, pattern, kind)
      super(db, "quants")
      @pattern = pattern
      @pattern = "all_pages" if @pattern.blank? || @pattern == '::'
      @pattern = Regexp.new(/#{Regexp.escape(@pattern)}/) unless @pattern == "all_pages"
      @kind = kind
      @resources = resources
      compute
    end

    def quants(resource)
      @quants[resource]
    end

    def compute
      selector = { :page => @pattern, :kind => @kind }
      fields = { :projection => _fields(["quant"].concat(@resources))}
      query, log = build_query("Quants.find", selector, fields)
      rows = with_conditional_caching(log) do |payload|
        rs = []
        query.each do |row|
          row.delete("_id")
          rs << row
        end
        payload[:rows] = rs.size
        rs
      end

      quants = @quants = {}
      while row = rows.shift
        quant = row["quant"]
        @resources.each do |f|
          if (v = row[f].to_i) > 0
            (quants[f] ||= Hash.new(0))[quant] += v
          end
        end
      end

      # logger.debug("QUANTS(#{@pattern.inspect}): #{@quants.inspect}")
    end

  end

end

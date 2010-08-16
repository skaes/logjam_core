module Logjam

  class Quants
    def initialize(db, resources, pattern, kind)
      @database = db
      @collection = @database["quants"]
      @pattern = pattern
      @pattern = "all_pages" if @pattern.blank?
      @pattern = Regexp.new(/#{@pattern}/) unless @pattern == "all_pages"
      @kind = kind
      @resources = resources
      compute
    end

    def quants(resource)
      @quants[resource]
    end

    def compute
      @quants = {}
      n = 0
      access_time = Benchmark.realtime do
        @collection.find({:page => @pattern, :kind => @kind}, {:fields => ["quant"].concat(@resources)}).each do |row|
          n += 1
          quant = row["quant"]
          @resources.each do |f|
            if (v = row[f].to_i) > 0
              (@quants[f] ||= Hash.new(0))[quant] += v
            end
          end
        end
      end
      logger.debug "MONGO quants: #{@pattern}, #{n} records, #{"%.5f" % (access_time)} seconds}"
    end

    def logger
      self.class.logger
    end

    def self.logger
      Rails.logger
    end

  end

end

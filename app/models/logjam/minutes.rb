module Logjam

  class Minutes < MongoModel

    def self.ensure_indexes(collection)
      ms = Benchmark.ms do
        collection.create_index([ ["page", Mongo::ASCENDING], ["minute", Mongo::ASCENDING] ], :background => true)
      end
      logger.debug "MONGO Minutes Indexes Creation: #{"%.1f" % (ms)} ms"
      collection
    end

    attr_reader :counts, :minutes

    def initialize(db, resources, pattern, page_names, interval=5)
      super(db, "minutes")
      @resources = resources
      @pattern = pattern
      @interval = interval
      @pattern = "all_pages" if @pattern.blank? || @pattern == "::"
      @pattern = "::#{@pattern}" if page_names.include?("::#{pattern}")
      @pattern = Regexp.new(/#{@pattern}/) unless @pattern == "all_pages" || page_names.include?(@pattern)
      if resources == ["fapdex"]
        @counters = ["page_count", "ajax_count"]
      elsif resources.include? "ajax_time"
        @counters = ["ajax_count"]
      else
        @counters = (@resources & Resource.frontend_resources).empty? ? ["count"] : ["page_count"]
      end
      @apdex = {}
      @apdex_score = {}
      compute(interval)
    end

    def exceptions
      @exceptions ||= extract_sub_hash('exceptions')
    end

    def js_exceptions
      @js_exceptions ||= extract_sub_hash('js_exceptions')
    end

    def callers
      @callers ||= extract_sub_hash('callers')
    end

    def response
      @response_codes ||= extract_sub_hash('response')
    end

    def severity
      @severity ||= extract_sub_hash('severity')
    end

    def exception_summary
      @excpetion_summary ||= exceptions.each_with_object(Hash.new(0)){|(_,h),s| h.each{|m,c| s[m] += c}}
    end

    def js_exception_summary
      @js_exception_summary ||= js_exceptions.each_with_object(Hash.new(0)){|(_,h),s| h.each{|m,c| s[m] += c}}
    end

    def apdex(section = :backend)
      @apdex[section] ||=
        begin
          sub_hash_name = section == :frontend ? 'fapdex' : 'apdex'
          extract_sub_hash(sub_hash_name)
        end
    end

    alias :fapdex :apdex

    def apdex_score(section = :backend)
      @apdex_score[section] ||= @minutes.keys.each_with_object(Hash.new(0)) do |m,h|
        h[m] = ((apdex(section)["satisfied"][m] + apdex(section)["tolerating"][m]/2.0) / counts[m])/@interval.to_f
      end
    end
    alias :fapdex_score :apdex_score

    private

    # extract a field stored as a sub hash of counters from the minutes records
    def extract_sub_hash(key)
      hash = Hash.new{|h,e| h[e] = Hash.new(0)}
      @minutes.each do |m,h|
        (h[key]||{}).each do |e,c|
          hash[e][m] = c
        end
      end
      hash
    end

    def compound_resources
      %w(apdex fapdex exceptions js_exceptions severity callers response)
    end

    def compute(interval)
      logger.debug "pattern: #{@pattern}, resources: #{@resources.inspect}"
      selector = {:page => @pattern}
      fields = {:fields => ["minute"].concat(@counters).concat(@resources)}

      query = "Minutes.find(#{selector.inspect},#{fields.inspect})"
      rows = with_conditional_caching(query) do |payload|
        rs = []
        @collection.find(selector, fields.clone).each do |row|
          row.delete("_id")
          rs << row if @counters.any?{|c| row[c].to_i > 0}
          # puts row.inspect
        end
        payload[:rows] = rs.size
        rs
      end

      # aggregate values according to given interval
      sums = {}
      counts = Hash.new(0.0)
      counter_resources = @resources - compound_resources
      hashed_resources = @resources & compound_resources
      while row = rows.shift
        count = @counters.map{|c| row[c].to_i}.sum || 0.0
        slot = row["minute"] / interval
        counts[slot] += count
        sum_sofar = (sums[slot] ||= Hash.new(0.0))
        counter_resources.each do |f|
          v = row[f].to_f
          v /= 40 if f == "allocated_bytes" # HACK!!!
          sum_sofar[f] += v
        end
        hashed_resources.each do |r|
          unless (h = sum_sofar[r]).is_a?(Hash)
            h = sum_sofar[r] = Hash.new(0)
          end
          if vals = row[r]
            vals.each do |f,v|
              h[f] += v.to_i
            end
          end
        end
      end

      @minutes = sums
      sums.each do |m,r|
        cnt = counts[m]
        r.each_key do |f|
          unless (v = r[f]).is_a?(Hash)
            r[f] = v/cnt
          end
        end
      end

      @counts = counts
      counts.each_key { |m| counts[m] /= interval.to_f }

      logger.debug "Minutes size #{@minutes.size}"
    end

  end
end

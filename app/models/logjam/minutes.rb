module Logjam

  class Minutes < MongoModel

    def self.ensure_indexes(collection, options = {})
      ms = Benchmark.ms do
        collection.indexes.create_one({"page" => 1, "minute" => 1 }, options)
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
        @counters = ["frontend_count"]
      elsif resources == ["papdex"]
        @counters = ["page_count"]
      elsif resources == ["xapdex"]
        @counters = ["ajax_count"]
      else
        if (resources & Resource.dom_resources).size > 0
          @counters = ["page_count"]
        elsif (@resources & Resource.frontend_resources).size > 0
          @counters = ["page_count", "ajax_count", "frontend_count"]
        else
          @counters = ["count"]
        end
      end
      @apdex = {}
      @apdex_score = {}
      compute(interval)
    end

    def exceptions
      @exceptions ||= extract_sub_hash('exceptions')
    end

    def soft_exceptions
      @soft_exceptions ||= extract_sub_hash('soft_exceptions')
    end

    def js_exceptions
      @js_exceptions ||= extract_sub_hash('js_exceptions')
    end

    def callers
      @callers ||= extract_sub_hash('callers')
    end

    def senders
      @senders ||= extract_sub_hash('senders')
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

    def soft_exception_summary
      @soft_excpetion_summary ||= soft_exceptions.each_with_object(Hash.new(0)){|(_,h),s| h.each{|m,c| s[m] += c}}
    end

    def js_exception_summary
      @js_exception_summary ||= js_exceptions.each_with_object(Hash.new(0)){|(_,h),s| h.each{|m,c| s[m] += c}}
    end

    def apdex(section = :backend)
      @apdex[section] ||=
        begin
          sub_hash_name = Apdex.apdex(section)
          extract_sub_hash(sub_hash_name)
        end
    end

    alias :fapdex :apdex

    def apdex_score(section = :backend)
      @apdex_score[section] ||=
        begin
          counts = @counts[Apdex.counter(section)]
          @minutes.keys.each_with_object(Hash.new(0)) do |m,h|
             h[m] = ((apdex(section)["satisfied"][m] + apdex(section)["tolerating"][m]/2.0) / counts[m])/@interval.to_f
          end
        end
    end
    alias :fapdex_score :apdex_score

    private

    # extract a field stored as a sub hash of counters from the minutes records
    def extract_sub_hash(key)
      fix_key = key == "callers" || key == "senders"
      hash = Hash.new{|h,e| h[e] = Hash.new(0)}
      @minutes.each do |m,h|
        (h[key]||{}).each do |e,c|
          if fix_key && !e.include?("@")
            app, rest = Logjam.extract_app(e)
            e = "#{app}@#{rest}"
          end
          hash[e][m] += c
        end
      end
      hash
    end

    def compound_resources
      %w(apdex fapdex papdex xapdex exceptions soft_exceptions js_exceptions severity callers senders response)
    end

    def self.counter_for_field(f)
      if f == "frontend_time"
        "frontend_count"
      elsif f == "ajax_time"
        "ajax_count"
      elsif Resource.frontend_resources.include?(f)
        "page_count"
      elsif Resource.dom_resources.include?(f)
        "page_count"
      else
        "count"
      end
    end

    COUNTER_MAP = Resource.all_resources.each_with_object(Hash.new(0))do |r,h|
      h[r] = counter_for_field r
    end

    def compute(interval)
      logger.debug "pattern: #{@pattern}, resources: #{@resources.inspect}"
      selector = { :page => @pattern }
      fields = { :projection => _fields(["minute"].concat(@counters).concat(@resources)) }
      query, log = build_query("Minutes.find", selector, fields)
      rows = with_conditional_caching(log) do |payload|
        rs = []
        query.each do |row|
          row.delete("_id")
          rs << row if @counters.any?{|c| row[c].to_i > 0}
          # puts row.inspect
        end
        payload[:rows] = rs.size
        rs
      end

      # aggregate values according to given interval
      sums = {}
      counts = Hash.new{ |h,k| h[k] = Hash.new(0.0) }
      maxs = {}
      maxed_resources = @resources.select{|r| r =~ /_max\z/}
      counted_resources = @resources - compound_resources - maxed_resources
      hashed_resources = @resources & compound_resources
      while row = rows.shift
        slot = row["minute"] / interval
        @counters.each do |c|
          counts[c][slot] += row[c].to_i
        end
        sum_sofar = (sums[slot] ||= Hash.new(0.0))
        counted_resources.each do |f|
          v = row[f].to_f
          v /= 40 if f == "allocated_bytes" # HACK!!!
          sum_sofar[f] += v
        end
        maxs_so_far = (maxs[slot] ||= Hash.new(0.0))
        maxed_resources.each do |r|
          next unless row.has_key?(r)
          new_val = row[r].to_f
          old_val = maxs_so_far[r]
          maxs_so_far[r] = new_val if new_val > old_val
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
      sums.each do |minute, resource_hash|
        resource_hash.each_key do |field|
          counter = COUNTER_MAP[field]
          cnt = counts[counter][minute]
          unless (v = resource_hash[field]).is_a?(Hash)
            resource_hash[field] = v/cnt
          end
        end
      end

      maxs.each do |minute, resource_hash|
        sums[minute].merge!(resource_hash)
      end

      @counts = counts
      counts.each do |counter, minute_hash|
        minute_hash.each_key do |minute|
          minute_hash[minute] /= interval.to_f
        end
      end

      logger.debug "Minutes size #{@minutes.size}"
    end

  end
end

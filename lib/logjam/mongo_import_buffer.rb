module Logjam

  class MongoImportBuffer

    GENERIC_FIELDS = %w(page host ip user_id started_at process_id minute session_id new_session response_code app env severity)

    TIME_FIELDS = Resource.time_resources

    CALL_FIELDS = Resource.call_resources - ["requests"]

    MEMORY_FIELDS = Resource.memory_resources + Resource.heap_resources - ["growth"]

    FIELDS = TIME_FIELDS + CALL_FIELDS + MEMORY_FIELDS

    QUANTIFIED_FIELDS = TIME_FIELDS + %w(allocated_objects allocated_bytes)

    SQUARED_FIELDS = FIELDS.inject({}) { |h, f| h[f] = "#{f}_sq"; h}

    def initialize(dbname)
      db = Logjam.mongo.db(dbname)
      @totals = db["totals"]
      @totals.create_index("page")

      @minutes = db["minutes"]
      @minutes.create_index([ ["page", Mongo::ASCENDING], ["minute", Mongo::ASCENDING] ])

      #     @hours = db["hours"]
      #     @hours.create_index([ ["page", Mongo::ASCENDING], ["hour", Mongo::ASCENDING] ])

      @quants = db["quants"]
      @quants.create_index([ ["page", Mongo::ASCENDING], ["kind", Mongo::ASCENDING], ["quant", Mongo::ASCENDING] ])

      @requests = db["requests"]
      @requests.create_index([ ["page", Mongo::ASCENDING] ])
      @requests.create_index([ ["response_code", Mongo::DESCENDING] ])
      @requests.create_index([ ["minute", Mongo::DESCENDING] ])
      @requests.create_index([ ["started_at", Mongo::DESCENDING] ])
      FIELDS.each{|f| @requests.create_index([ [f, Mongo::DESCENDING] ])}

      setup_buffers
      @import_threshold = Logjam.import_threshold
    end

    def add(entry)
      severity = entry[:severity]
      page = entry[:page]
      page << "#unknown_method" unless page =~ /#/
      minute = entry[:minute]
      response_code = entry[:response_code]
      user_id = entry[:user_id]
      total_time = entry[:total_time]
      lines = entry.delete(:lines)
      fields = entry.stringify_keys
      fields.delete_if{|k,v| v==0 || GENERIC_FIELDS.include?(k) }
      fields.keys.each{|k| fields[squared_field(k)] = (v=fields[k].to_f)*v}

      pmodule = "::"
      pmodule << $1 if page =~ /^(.+?)::/ || page =~ /^([^:#]+)#/

      increments = {"count" => 1}.merge!(fields)
      [page, "all_pages", pmodule].each do |p|
        increments.each do |f,v|
          (@minutes_buffer[[p,minute]] ||= Hash.new(0.0))[f] += v
        end
      end

      user_experience =
        if total_time >= 2000 || response_code == 500 then {"apdex.frustrated" => 1}
        elsif total_time < 100 then {"apdex.happy" => 1, "apdex.satisfied" => 1}
        elsif total_time < 500 then {"apdex.satisfied" => 1}
        elsif total_time < 2000 then {"apdex.tolerating" => 1}
        else raise "oops: #{tt.inspect}"
        end

      increments.merge!(user_experience)
      increments["response.#{response_code}"] = 1

      [page, "all_pages", pmodule].each do |p|
        increments.each do |f,v|
          (@totals_buffer[p] ||= Hash.new(0.0))[f] += v
        end
      end

      #     hour = minute / 60
      #     [page, "all_pages", pmodule].each do |p|
      #       increments.each do |f,v|
      #         (@hours_buffer[[p,hour]] ||= Hash.new(0))[f] += v
      #       end
      #     end

      QUANTIFIED_FIELDS.each do |f|
        next unless x=fields[f]
        if f == "allocated_objects"
          kind = "m"
          d = 10000
        elsif f == "allocated_bytes"
          kind = "m"
          d = 100000
        else
          kind = "t"
          d = 100
        end
        x = ((x.floor/d).ceil+1)*d
        [page, "all_pages"].each do |p|
          (@quants_buffer[[p,kind,x]] ||= Hash.new(0.0))[f] += 1
        end
      end

      request = {"severity" => severity, "page" => page, "minute" => minute, "response_code" => response_code, "user_id" => user_id, "lines" => lines}.merge!(fields)
      @requests.insert(request) if interesting?(request)
    end

    def flush
      flush_totals_buffer
      flush_minutes_buffer
      # flush_hours_buffer
      flush_quants_buffer
    end

    private

    def squared_field(f)
      SQUARED_FIELDS[f] || raise("unknown field #{f}")
    end

    def interesting?(request)
      request["total_time"].to_i > @import_threshold ||
        request["heap_growth"].to_i > 0 ||
        request["response_code"].to_i == 500
    end

    def setup_buffers
      @quants_buffer = {}
      @totals_buffer = {}
      @minutes_buffer = {}
      # @hours_buffer = {}
    end

    UPSERT_ONE = {:upsert => true, :multi => false}

    def flush_quants_buffer
      @quants_buffer.each do |(p,k,q),inc|
        @quants.update({"page" => p, "kind" => k, "quant" => q}, { '$inc' => inc }, UPSERT_ONE)
      end
      @quants_buffer.clear
    end

    def flush_minutes_buffer
      @minutes_buffer.each do |(p,m),inc|
        @minutes.update({"page" => p, "minute" => m}, { '$inc' => inc }, UPSERT_ONE)
      end
      @minutes_buffer.clear
    end

    #   def flush_hours_buffer
    #     @hours_buffer.each do |(p,h),inc|
    #       @hours.update({"page" => p, "hour" => h}, { '$inc' => inc }, UPSERT_ONE)
    #     end
    #     @hours_buffer.clear
    #   end

    def flush_totals_buffer
      @totals_buffer.each do |(p,inc)|
        @totals.update({"page" => p}, { '$inc' => inc }, UPSERT_ONE)
      end
      @totals_buffer.clear
    end

  end
end

require 'amqp'
require 'json'
require 'set'

module Logjam

  class MongoImportBuffer

    attr_reader :iso_date_string

    def initialize(dbname, app, env, iso_date_string)
      @app = app
      @env = env
      @iso_date_string = iso_date_string

      database  = Logjam.mongo.db(dbname)
      @totals   = Totals.ensure_indexes(database["totals"])
      @minutes  = Minutes.ensure_indexes(database["minutes"])
      @quants   = Quants.ensure_indexes(database["quants"])
      @requests = Requests.ensure_indexes(database["requests"])

      #     @hours = db["hours"]
      #     @hours.create_index([ ["page", Mongo::ASCENDING], ["hour", Mongo::ASCENDING] ])

      @import_threshold  = Logjam.import_threshold
      @generic_fields    = Set.new(Requests::GENERIC_FIELDS - %w(page response_code) + %w(action code engine))
      @quantified_fields = Requests::QUANTIFIED_FIELDS
      @squared_fields    = Requests::SQUARED_FIELDS

      setup_buffers
    end

    def add(entry)
      host = entry["host"]
      ip = entry["ip"]
      page = entry["action"] || "Unknown"
      page << "#unknown_method" unless page =~ /#/
      unless response_code = entry["code"]
        $stderr.puts "no response code"
        $stderr.puts entry.to_yaml
        response_code = 500
      end
      user_id = entry["user_id"]
      total_time = entry["total_time"] || 1
      started_at = entry["started_at"]

      severity = entry["severity"]
      unless lines = entry.delete("lines")
        $stderr.puts "no request lines"
        $stderr.puts entry.to_yaml
        lines = []
      end
      severity ||= lines.map{|s,t,l| s}.max || 5

      # mongo field names must not contain dots
      if exceptions = entry["exceptions"]
        exceptions.each{|e| e.gsub!('.','_')}
      end

      fields = entry
      add_allocated_memory(fields)
      add_other_time(fields, total_time)
      minute = add_minute(fields)

      fields.delete_if{|k,v| v==0 || @generic_fields.include?(k)}
      fields.keys.each{|k| fields[squared_field(k)] = (v=fields[k].to_f)*v}

      pmodule = "::"
      if page =~ /^(.+?)::/ || page =~ /^([^:#]+)#/
        pmodule << $1
        @modules << pmodule
      end

      increments = {"count" => 1}.merge!(fields)

      user_experience =
        if total_time >= 2000 || response_code == 500 then {"apdex.frustrated" => 1}
        elsif total_time < 100 then {"apdex.happy" => 1, "apdex.satisfied" => 1}
        elsif total_time < 500 then {"apdex.satisfied" => 1}
        elsif total_time < 2000 then {"apdex.tolerating" => 1}
        else raise "oops: #{total_time.inspect}"
        end

      increments.merge!(user_experience)
      increments["response.#{response_code}"] = 1
      # only store severities which indicate warnings/errors
      increments["severity.#{severity}"] = 1 if severity > 1

      exceptions.each do |e|
        increments["exceptions.#{e}"] = 1
      end if exceptions

      [page, "all_pages", pmodule].each do |p|
        increments.each do |f,v|
          (@minutes_buffer[[p,minute]] ||= Hash.new(0.0))[f] += v
        end
      end

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

      @quantified_fields.each do |f|
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

      request = {
        "severity" => severity, "page" => page, "minute" => minute, "response_code" => response_code,
        "host" => host, "user_id" => user_id, "lines" => lines
      }.merge!(fields)
      request["exceptions"] = exceptions if exceptions
      request["ip"] = ip if ip

      if interesting?(request)
        begin
          request_id = @requests.insert(request)
        rescue Exception
          $stderr.puts "Could not insert document: #{$!}"
        end
      end

      if severity > 1
        # extract the first error found (duplicated code from logjam helpers)
        description = ((lines.detect{|(s,t,l)| s >= 2})[2].to_s)[0..80] rescue "--- unknown ---"
        error_info = { "request_id" => request_id.to_s,
                       "severity" => severity, "action" => page,
                       "description" => description, "time" => started_at }
        ["all_pages", pmodule].each do |p|
          (@errors_buffer[p] ||= []) << error_info
        end
      end

    end

    def flush
      publish_totals
      publish_errors
      flush_totals_buffer
      flush_minutes_buffer
      # flush_hours_buffer
      flush_quants_buffer
    end

    private

    def other_time_resources
      @@other_time_resources ||= Resource.time_resources - %w(total_time gc_time)
    end

    def add_other_time(entry, total_time)
      entry["other_time"] = total_time - other_time_resources.inject(0.0){|s,r| s += (entry[r] || 0)}
    end

    def extract_minute(iso_string)
      60 * iso_string[11..12].to_i + iso_string[14..15].to_i
    end

    def add_allocated_memory(entry)
      if !(allocated_memory = entry["allocated_memory"]) && (allocated_objects = entry["allocated_objects"])
        # assume 64bit ruby
        entry["allocated_memory"] = entry["allocated_bytes"].to_i + allocated_objects * 40
      end
    end

    def add_minute(entry)
      entry["minute"] = extract_minute(entry["started_at"])
    end

    def squared_field(f)
      @squared_fields[f] || raise("unknown field #{f}")
    end

    def interesting?(request)
      request["total_time"].to_f > @import_threshold ||
        request["severity"] > 1 ||
        request["response_code"].to_i >= 400 ||
        request["exceptions"] ||
        request["heap_growth"].to_i > 0
    end

    def setup_buffers
      @quants_buffer = {}
      @totals_buffer = {}
      @minutes_buffer = {}
      # @hours_buffer = {}
      @errors_buffer = {}
      @modules = Set.new(%w(all_pages))
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

    def self.exchange(app, env)
      (@exchange||={})["#{app}-#{env}"] ||=
        begin
          channel = AMQP::Channel.new(AMQP.connect(:host => live_stream_host))
          channel.auto_recovery = true
          channel.topic("logjam-performance-data-#{app}-#{env}")
        end
    end

    def self.live_stream_host
      @live_stream_host ||= Logjam.streams["livestream-#{Rails.env}"].host
    end

    def exchange
      @exchange ||= self.class.exchange(@app, @env)
    end

    NO_REQUEST = {"count" => 0}

    def publish_totals
      # always publish something every second to the perf data exchange
      @modules.each { |p| publish(p, @totals_buffer[p] || NO_REQUEST) }
    end

    def publish_errors
      @modules.each do |p|
        if errs = @errors_buffer[p]
          # $stderr.puts errs
          publish(p, errs)
        end
      end
      @errors_buffer.clear
    end

    def publish(p, inc)
      exchange.publish(inc.to_json, :key => p.sub(/^::/,'').downcase)
    rescue
      $stderr.puts "could not publish performance/error data: #{$!}"
    end
  end
end

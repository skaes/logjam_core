# encoding: utf-8
require 'set'

module Logjam

  class RequestProcessor
    include Logjam::LogWithProcessId

    def initialize(request_collection)
      @requests = request_collection
      @import_threshold  = Logjam.import_threshold
      @generic_fields    = Set.new(Requests::GENERIC_FIELDS - %w(page response_code) + %w(action code engine))
      @quantified_fields = Requests::QUANTIFIED_FIELDS
      @squared_fields    = Requests::FIELDS.map{|f| [f,"#{f}_sq"]}
      @other_time_resources = Resource.time_resources - %w(total_time gc_time)
      @modules = Set.new(%w(all_pages))
      reset_buffers
    end

    def reset_buffers
      @quants_buffer = {}
      @totals_buffer = {}
      @minutes_buffer = {}
      @errors_buffer = {}
      @request_count = 0
    end
    private :reset_buffers

    def reset_state
      state = {
        :totals => @totals_buffer,
        :minutes => @minutes_buffer,
        :quants => @quants_buffer,
        :errors => @errors_buffer,
        :modules => @modules,
        :count => @request_count
      }
      reset_buffers
      state
    end

    def add(entry)
      @request_count += 1
      page = entry["page"] = (entry.delete("action") || "Unknown")
      page << "#unknown_method" unless page =~ /#/
      pmodule = "::"
      if page =~ /^(.+?)::/ || page =~ /^([^:#]+)#/
        pmodule << $1
        @modules << pmodule
      end

      response_code = entry["response_code"] = (entry.delete("code") || 500).to_i
      total_time    = (entry["total_time"] ||= 1.0)
      started_at    = entry["started_at"]
      lines         = (entry["lines"] ||= [])
      severity      = (entry["severity"] ||= lines.map{|s,t,l| s}.max || 5)

      # mongo field names must not contain dots
      if exceptions = entry["exceptions"]
        if exceptions.empty?
          entry.delete("exceptions")
          exceptions = nil
        else
          exceptions.each{|e| e.gsub!('.','_')}
        end
      end

      add_allocated_memory(entry)
      add_other_time(entry, total_time)
      minute = add_minute(entry)

      increments = {"count" => 1}
      add_squared_fields(increments, entry)

      if total_time >= 2000 || response_code >= 500 then
        increments["apdex.frustrated"] = 1
      elsif total_time < 100 then
        increments["apdex.happy"] = increments["apdex.satisfied"] = 1
      elsif total_time < 500 then
        increments["apdex.satisfied"] = 1
      elsif total_time < 2000 then
        increments["apdex.tolerating"] = 1
      end

      increments["response.#{response_code}"] = 1

      # only store severities which indicate warnings/errors
      increments["severity.#{severity}"] = 1 if severity > 1

      exceptions.each do |e|
        increments["exceptions.#{e}"] = 1
      end if exceptions

      add_minutes_and_totals(increments, page, pmodule, minute)

      #     hour = minute / 60
      #     [page, "all_pages", pmodule].each do |p|
      #       increments.each do |f,v|
      #         (@hours_buffer[[p,hour]] ||= Hash.new(0))[f] += v
      #       end
      #     end

      add_quants(increments, page)

      if interesting?(entry)
        begin
          if request_id = entry.delete("request_id")
            l = request_id.length
            if l == 32
              oid = BSON::Binary.new(request_id, BSON::Binary::SUBTYPE_UUID) rescue nil
            elsif l == 24
              oid = BSON::ObjectId.new(request_id) rescue nil
            end
            entry["_id"] = oid if oid
          end
          request_id = @requests.insert(entry)
        rescue Exception => e
          if e.message =~ /String not valid UTF-8|key.*must not contain '.'|Cannot serialize the Numeric type BigDecimal/
            begin
              log_error "fixing json: #{e.class}(#{e})"
              entry = try_to_fix(entry)
              request_id = @requests.insert(entry)
              log_info "request insertion succeeed"
            rescue Exception => e
              log_error "Could not insert document: #{e.class}(#{e})"
              log_error entry.inspect
            end
          else
            log_error "Could not insert document: #{e.class}(#{e})"
            log_error entry.inspect
          end
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

    private

    DOT_REPLACEMENT = '∙'
    raise "fried turtles on my plate!" unless DOT_REPLACEMENT.encoding == Encoding::UTF_8

    def try_to_fix(entry)
      case entry
      when Hash
        h = Hash.new
        entry.each_pair do |k,v|
          new_key = k.is_a?(String) ? ensure_utf8(k).gsub('.', DOT_REPLACEMENT) : try_to_fix(k)
          h[new_key] = try_to_fix(v)
        end
        h
      when Array
        entry.collect!{|e| try_to_fix(e)}
      when String
        ensure_utf8(entry)
      when BigDecimal
        entry.to_f
      else
        entry
      end
    end

    LIKELY_ENCODINGS =
      [
       Encoding::Windows_1252, # English and some other Western languages (superset of ISO8859_1)
       Encoding::Windows_1250, # Central European and Eastern European languages
       Encoding::Windows_1251, # languages that use the Cyrillic script
       Encoding::Windows_1254  # Turkish
      ]

    def ensure_utf8(string)
      return string if string.ascii_only?
      # Try it as UTF-8 directly
      if string.frozen?
        log_error "frozen string: #{string}"
        string = string.dup
      end
      string.force_encoding('UTF-8')
      return string if string.valid_encoding?
      # bad luck. try some other encodings.
      string.force_encoding('ASCII-8BIT')
      LIKELY_ENCODINGS.each do |encoding|
        begin
          if res = string.encode(Encoding::UTF_8, encoding)
            log_error "changed encoding to #{encoding.name}: #{res}"
            return res
          end
        rescue EncodingError
        end
      end
      # give up and replace unkown characters
      log_error "no valid encoding found"
      string.encode!('UTF-8', :invalid => :replace, :undef => :replace)
    end

    def add_other_time(entry, total_time)
      ot = total_time.to_f
      @other_time_resources.each {|r| (v = entry[r]) && (ot -= v)}
      entry["other_time"] = ot
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

    def add_squared_fields(increments, entry)
      @squared_fields.each do |f,fsq|
        next if (v = entry[f]).nil?
        if v == 0
          entry.delete(f)
        else
          increments[f] = (v = v.to_f)
          increments[fsq] = v*v
        end
      end
    end

    def add_minutes_and_totals(increments, page, pmodule, minute)
      [page, "all_pages", pmodule].each do |p|
        mbuffer = (@minutes_buffer[[p,minute]] ||= Hash.new(0.0))
        tbuffer = (@totals_buffer[p] ||= Hash.new(0.0))
        increments.each do |f,v|
          mbuffer[f] += v
          tbuffer[f] += v
        end
      end
    end

    def add_quants(increments, page)
      @quantified_fields.each do |f|
        next unless x=increments[f]
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
    end

    def interesting?(request)
      request["total_time"].to_f > @import_threshold ||
        request["severity"] > 1 ||
        request["response_code"].to_i >= 400 ||
        request["exceptions"] ||
        request["heap_growth"].to_i > 0
    end

  end
end

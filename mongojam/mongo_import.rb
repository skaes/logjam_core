#!/usr/bin/env ruby

require 'rubygems'
require 'benchmark'
require File.expand_path('../config/initializers/mongo')
require File.expand_path('../app/models/logjam')

if RUBY_VERSION > "1.9"
  require "csv"
  ::FasterCSV = CSV unless defined? FasterCSV
else
  require "fastercsv"
end

# CREATE TABLE `log_data_2010_06_02` (
#   `id` int(11) NOT NULL auto_increment,
#   `host` varchar(255) collate utf8_unicode_ci NOT NULL,
#   `process_id` int(11) NOT NULL,
#   `user_id` int(11) NOT NULL,
#   `page` varchar(255) collate utf8_unicode_ci NOT NULL,
#   `minute1` int(11) NOT NULL,
#   `minute2` int(11) NOT NULL,
#   `minute5` int(11) NOT NULL,
#   `started_at` datetime NOT NULL,
#   `response_code` int(11) NOT NULL,
#   `session_id` varchar(255) collate utf8_unicode_ci NOT NULL,
#   `new_session` tinyint(1) NOT NULL,
#12 `total_time` float NOT NULL,
#   `view_time` float NOT NULL,
#   `db_time` float NOT NULL,
#   `api_time` float NOT NULL,
#   `search_time` float NOT NULL,
#   `other_time` float NOT NULL,
#   `gc_time` float NOT NULL,
#   `memcache_time` float NOT NULL,
#   `db_calls` int(11) NOT NULL,
#   `db_sql_query_cache_hits` int(11) NOT NULL,
#   `api_calls` int(11) NOT NULL,
#   `memcache_calls` int(11) NOT NULL,
#   `memcache_misses` int(11) NOT NULL,
#   `search_calls` int(11) NOT NULL,
#   `gc_calls` int(11) NOT NULL,
#   `heap_size` int(11) NOT NULL,
#   `heap_growth` int(11) NOT NULL,
#   `allocated_objects` int(11) NOT NULL,
#   `allocated_bytes` int(11) NOT NULL,
#   `allocated_memory` int(11) NOT NULL,

TIME_FIELDS = %w(
        total_time
        view_time
        db_time
        api_time
        search_time
        other_time
        gc_time
        memcache_time
)
FIELDS = TIME_FIELDS + %w(
        db_calls
        db_sql_query_cache_hits
        api_calls
        memcache_calls
        memcache_misses
        search_calls
        gc_calls
        heap_size
        heap_growth
        allocated_objects
        allocated_bytes
        allocated_memory
)

SQUARED_FIELDS = FIELDS.inject({}) { |h, f| h[f] = "#{f}_sq"; h}

db = MONGODB.db(Logjam.db_name("2010-06-21"))
$totals = db["totals"]
$totals.create_index("page")

$minutes = db["minutes"]
$minutes.create_index([ ["page", Mongo::ASCENDING], ["minute", Mongo::ASCENDING] ])

$quants = db["quants"]
$quants.create_index([ ["page", Mongo::ASCENDING], ["kind", Mongo::ASCENDING], ["quant", Mongo::ASCENDING] ])

requests = db["requests"]
requests.create_index([ ["page", Mongo::ASCENDING] ])
requests.create_index([ ["response_code", Mongo::DESCENDING] ])
FIELDS.each{|f| requests.create_index([ [f, Mongo::DESCENDING] ])}

def interesting?(request)
  request["heap_growth"].to_i > 0 ||
    request["total_time"].to_i > 750 ||
    request["response_code"].to_i == 500
end

UPSERT_ONE = {:upsert => true, :multi => false}
n = 0
file_path = ARGV.shift

$quants_buffer = {}
$totals_buffer = {}
$minutes_buffer = {}

def flush_quants_buffer
  $quants_buffer.each do |(p,k,q),inc|
    $quants.update({"page" => p, "kind" => k, "quant" => q}, { '$inc' => inc }, UPSERT_ONE)
  end
  $quants_buffer.clear
end

def flush_minutes_buffer
  $minutes_buffer.each do |(p,m),inc|
    $minutes.update({"page" => p, "minute" => m}, { '$inc' => inc }, UPSERT_ONE)
  end
  $minutes_buffer.clear
end

def flush_totals_buffer
  $totals_buffer.each do |(p,inc)|
    $totals.update({"page" => p}, { '$inc' => inc }, UPSERT_ONE)
  end
  $totals_buffer.clear
end

puts "importing #{file_path}"

load_time = Benchmark.realtime do
  csv = FasterCSV.open(file_path)
  loop do
    begin
      break unless r = csv.shift
      n += 1
      page = r[4]
      minute = r[7].to_i # minute5
      response_code = r[9].to_i
      response_code_str = r[9]
      user_id = r[3].to_i
      total_time = r[12].to_f
      date = r[8][0,10]
      fields = {
        "total_time" => total_time,
        "view_time" => r[13].to_f,
        "db_time" => r[14].to_f,
        "api_time" => r[15].to_f,
        "search_time" => r[16].to_f,
        "other_time" => r[17].to_f,
        "gc_time" => r[18].to_f,
        "memcache_time" => r[19].to_f,
        "db_calls" => r[20].to_f,
        "db_sql_query_cache_hits" => r[21].to_f,
        "api_calls" => r[22].to_f,
        "memcache_calls" => r[23].to_f,
        "memcache_misses" => r[24].to_f,
        "search_calls" => r[25].to_f,
        "gc_calls" => r[26].to_f,
        "heap_size" => r[27].to_f,
        "heap_growth" => r[28].to_f,
        "allocated_objects" => r[29].to_f,
        "allocated_bytes" => r[30].to_f,
        "allocated_memory" => r[31].to_f
      }
      fields.delete_if{|k,v| v==0}
      fields.keys.each{|k| fields[SQUARED_FIELDS[k]] = (v=fields[k])*v}

      increments = {"count" => 1}.merge!(fields)
      [page, "all_pages"].each do |p|
        increments.each do |f,v|
          ($minutes_buffer[[p,minute]] ||= Hash.new(0))[f] += v
        end
      end

      flush_minutes_buffer if (n % 250) == 0

      user_experience =
        if total_time >= 2000 || response_code == 500 then "frustrated"
        elsif total_time < 100 then "happy"
        elsif total_time < 500 then "satisfied"
        elsif total_time < 2000 then "tolerating"
        else raise "oops: #{tt.inspect}"
        end

      increments.merge!("apdex.#{user_experience}" => 1, "response.#{response_code_str}" => 1)

      [page, "all_pages"].each do |p|
        increments.each do |f,v|
          ($totals_buffer[p] ||= Hash.new(0))[f] += v
        end
      end

      flush_totals_buffer if (n % 250) == 0

      (TIME_FIELDS+%w(allocated_objects allocated_bytes)).each do |f|
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
          ($quants_buffer[[p,kind,x]] ||= Hash.new(0))[f] += 1
        end
      end

      flush_quants_buffer if (n % 1500) == 0

      request = {"page" => page, "minute" => minute, "response_code" => response_code, "user_id" => user_id}.merge!(fields)
      requests.insert(request) if interesting?(request)

      break if n >= 1000
    rescue CSV::MalformedCSVError
      $stderr.puts "ignored malformed csv line"
    end
  end
  flush_totals_buffer
  flush_minutes_buffer
  flush_quants_buffer
  csv.close
end

puts "#{file_path}: insertion time: #{"%.2f" % load_time} seconds, #{"%.2f" % (n/load_time)} requests per second"

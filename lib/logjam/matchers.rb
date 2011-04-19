module Logjam

  # This module provides methods to extract information out of log lines.
  # A matcher method must exhibit the following behavior:
  #
  #   accept a log line and extract info as a hash where the domain corresponds to som db column.
  #   return false (or nil) if the line cannot be matched.
  #
  # NOTE: Most of the configuration options are at the end of this file. But you also need
  #       to pay attention to the LOG_LINE_SPLITTER.
  module Matchers

    # this regexp is used to prefilter log files with egrep|zegrep (which can speed up things quite a bit)
#    PRE_MATCH = 'Completed|Processing|Session ID'

    # log line format @XING
    # WARN  Jul 08 07:42:53 ext-xeapp52-5 rails[31023] user[Anonymous]: ... rails log content ...
    # INFO  Jul 08 07:42:53 ext-xeapp52-5 rails[31023] user[243242356]: ... rails log content ...
    #
    # standard syslog format would be
    # Jul 08 07:42:53 ext-xeapp52-5 rails[31023]: ... rails log content ...
    # the following matcher works in both cases
    # unlike the other matchers, this one returns an array of [severity1, timestamp, host, process_id, severity2, user_id, engine, payload]
    SYSLOG_LINE_SPLITTER = lambda do |line|
      line =~ /^(?:([A-Z]+)\s+)?((?:\S+) (?:\S+) (?:\S+)) ([\S]+) [\S]+\[(\d+)\](?:: (\S+))?(?: user\[(.+?)\])?(?: engine\[(.+?)\])?: (.*)/ and
        Regexp.last_match.captures
    end

    # Use this splitter if you are using the default Rails logger. However, if you have multiple
    # processes logging to the same log file (eg with Passenger), you will end up with a mess.
    RAILS_LOG_LINE_SPLITTER = lambda do |line|
      process_id = 0
      user_id = nil
      ['localhost', process_id, user_id, line]
    end

    # CONFIGURE ME: Pick one of the splitters above.
    # LOG_LINE_SPLITTER = RAILS_LOG_LINE_SPLITTER
    LOG_LINE_SPLITTER = SYSLOG_LINE_SPLITTER

    PROCESSING = lambda do |line|
      line =~ /^Processing ([\S]+)(?: .*\(for (.+) at (.+)\))?/ and
        { :page => $1, :ip => $2, :started_at => ($3 || Time.now.to_s(:db)) }
    end

    # Processing by AppsController#update_state as JS
    PROCESSING_RAILS3 = lambda do |line|
      line =~ /^Processing by ([\S]+).*/ and
        { :page => $1 }
    end

    # Started GET "/apps/update_state" for 87.193.61.218 at Tue Sep 14 22:07:18 +0200 2010
    STARTED_RAILS3 = lambda do |line|
      line =~ /^Started .+ for (.+) at (.+)/ and
        { :ip => $1, :started_at => DateTime.parse($2).to_s }
    end

    # default rails session log line. optional matcher.
    SESSION_RAILS = lambda do |line|
      line =~ /^Session ID: ([\S]+)/ and
        { :session_id => $1 }
    end

    # @XING we also log whether the session was created during request processing
    SESSION_XING = lambda do |line|
      line =~ /^Session ID: ([\S]+) \(([XN])\)/ and
        { :session_id => $1, :new_session => ($2 == 'N') ? 1 : 0 }
    end

    # default rails completed line. mandatory matcher.
    # Completed in 1517ms (View: 26, DB: 26) | 200 OK [http://localhost/marketplace/]
    COMPLETED_RAILS = lambda do |line|
      line =~ /^Completed in ([\S]+)ms \(View: ([\S]+), DB: ([\S]+)\) \| (\d+) / and
        {
          :total_time => $1.to_f,
          :view_time => $2.to_f,
          :db_time => $3.to_f,
          :response_code => $4.to_i,
        }
    end

    # time_bandits, either the simple, out-of-the-box format
    #   Jan 13 16:58:38 starbuck-2 rails[86742]:  Completed in 238.974ms (View: 61.361, DB: 41.915(14,1)) | 200 OK [http: ...]
    # or with memcache and memory resources, via gchacks
    #   Jan 13 16:58:38 starbuck-2 rails[86742]: Completed in 174.696ms (View: 59.062, DB: 13.954(14,2), MC: 0.000(0r,0m), GC: 0.000(0), HP: 0(450818,103822,3233093)) | 200 OK
    # see http://github.com/skaes/matzruby (branch ruby187pl202patched) or Ruby Enterprise Edition
    COMPLETED_TIME_BANDITS = lambda do |line|
      line =~ /^Completed in ([\S]+)ms \(View: ([\S]+), DB: ([\S]+)\((\d+)(?:,(\d+))?\)(?:, MC: ([\S]+)\((\d+)r,(\d+)m\))?(?:, GC: ([\S]+)\((\d+)\))?(?:, HP: ([\S]+)\((\d+),(\d+),(\d+)\))?\) \| (\d+)? / and
        {
          :total_time => $1.to_f,
          :view_time => $2.to_f,
          :db_time => $3.to_f,
          :db_calls => $4.to_i,
          :db_sql_query_cache_hits => $5.to_i,
          :memcache_time => $6.to_f,
          :memcache_calls => $7.to_i,
          :memcache_misses => $8.to_i,
          :gc_time => $9.to_f,
          :gc_calls => $10.to_i,
          :heap_growth => $11.to_i,
          :heap_size => $12.to_i,
          :allocated_objects => $13.to_i,
          :allocated_bytes => $14.to_i,
          :response_code => $15.to_i,
        }
    end

    # completed line regexp: complicated by the fact that the log file
    # format @XING changed over time and we want to be able to parse old logfiles
    #
    # Aug 09 14:33:18 somehost rails[12132] user[Anonymous] engine[jobs]: Completed in 472.898ms (View: 306.690, DB: 12.239(1,0), API: 0.000(0), SR: 112.595(1), MC: 10.867(4r,0m), GM: 0.000(0), GC: 0.000(0), HP: 0(2000001,169014,5889106,1137730)) | 200 OK [...]
    # Aug 26 15:37:29 pc-skaes-3 rails[74535] user[dddddddd]: Completed in 1517.781ms (View: 26.129, DB: 26.009(17,0), API: 41.166(1), SR: 30.590(3), MC: 6.447(9r,0m), GC: 628.893(6), HP: 0(1616240,591402,35515800)) | 200 OK ...]
    # Jul 27 16:25:29 pc-skaes-3 rails[3161] user[ddddddd]: Completed in 2352.498ms (View: 183.980, DB: 53.292(15), API: 46.657(1), SR: 7.638(3), MC: 6.345(9r,0m), GC: 970.501(10)) | 200 OK [...]
    # Jun 28 06:00:49 somehost rails[25944] user[Anonymous]: Completed in 176.044ms (View: 0.000, DB: 0.000(0), API: 0.000(0), SR: 0.000(0), MC: 2.218(1r,1m)) |  [...url...]
    COMPLETED_XING = lambda do |line|
      line =~ /^Completed in ([\S]+)ms \((?:View: ([\S]+), )?DB: ([\S]+)\((\d+)(?:,(\d+))?\), API: ([\S]+)\((\d+)\), SR: ([\S]+)\((\d+)\), MC: ([\S]+)\((\d+)r,(\d+)m\)(?:, GM: ([\S]+)\((\d+)\))?(?:, GC: ([\S]+)\((\d+)\))?(?:, HP: ([\S]+)\((\d+),(\d+),(\d+)(?:,(\d+))?\))?\)(?: \| (\d+)? )?/ and
        {
          :total_time => $1.to_f,
          :view_time => $2.to_f,
          :db_time => $3.to_f,
          :db_calls => $4.to_i,
          :db_sql_query_cache_hits => $5.to_i,
          :api_time => $6.to_f,
          :api_calls => $7.to_i,
          :search_time => $8.to_f,
          :search_calls => $9.to_i,
          :memcache_time => $10.to_f,
          :memcache_calls => $11.to_i,
          :memcache_misses => $12.to_i,
          :gearman_time => $13.to_f,
          :gearman_calls => $14.to_i,
          :gc_time => $15.to_f,
          :gc_calls => $16.to_i,
          :heap_growth => $17.to_i,
          :heap_size => $18.to_i,
          :allocated_objects => $19.to_i,
          :allocated_bytes => $20.to_i,
          :live_data_set_size => $21.to_i,
          :response_code => $22.to_i
      }.delete_if{|k,v| v == 0}
    end

    RAILS3_COMPLETED_REGEX = %r{^
      (?<views>Views:\s(?<view_time>\S+)ms){0}

      (?<db>ActiveRecord:\s(?<db_time>\S+)\((?<db_calls>\d+),(?<db_sql_query_cache_hits>\d+)\)){0}

      (?<api>API:\s(?<api_time>\S+)\((?<api_calls>\d+)\)){0}

      (?<search>SR:\s(?<search_time>\S+)\((?<search_calls>\d+)\)){0}

      (?<memcache>MC:\s(?<memcache_time>\S+)\((?<memcache_calls>\d+)r,(?<memcache_misses>\d+)m\)){0}

      (?<gearman>GM:\s(?<gearman_time>\S+)\((?<gearman_calls>\d+)\)){0}

      (?<rest>REST:\s(?<rest_time>\S+)\((?<rest_calls>\d+)\)){0}

      (?<gc>GC:\s(?<gc_time>\S+)\((?<gc_calls>\d+)\)){0}

      (?<heap>HP:\s(?<heap_growth>\S+)\((?<heap_size>\d+),(?<allocated_objects>\d+),(?<allocated_bytes>\d+),(?<live_data_set_size>\d+)\)){0}

      (?<elem>\g<db>|\g<api>|\g<views>|\g<search>|\g<memcache>|\g<gearman>|\g<rest>|\g<gc>|\g<heap>){0}

      Completed\s(?<response_code>\d+)\s.+\sin\s(?<total_time>\S+)ms(?:\s\(\g<elem>(\s\|\s\g<elem>)*\))?
    }x

    COMPLETED_RAILS3 = lambda do |line|
      (md = RAILS3_COMPLETED_REGEX.match(line)) and {
        :total_time              => md[:total_time].to_f,
        :view_time               => md[:view_time].to_f,
        :db_time                 => md[:db_time].to_f,
        :db_calls                => md[:db_calls].to_i,
        :db_sql_query_cache_hits => md[:db_sql_query_cache_hits].to_i,
        :api_time                => md[:api_time].to_f,
        :api_calls               => md[:api_calls].to_i,
        :search_time             => md[:search_time].to_f,
        :search_calls            => md[:search_calls].to_i,
        :memcache_time           => md[:memcache_time].to_f,
        :memcache_calls          => md[:memcache_calls].to_i,
        :memcache_misses         => md[:memcache_misses].to_i,
        :gearman_time            => md[:gearman_time].to_f,
        :gearman_calls           => md[:gearman_calls].to_i,
        :rest_time               => md[:rest_time].to_f,
        :rest_calls              => md[:rest_calls].to_i,
        :gc_time                 => md[:gc_time].to_f,
        :gc_calls                => md[:gc_calls].to_i,
        :heap_growth             => md[:heap_growth].to_i,
        :heap_size               => md[:heap_size].to_i,
        :allocated_objects       => md[:allocated_objects].to_i,
        :allocated_bytes         => md[:allocated_bytes].to_i,
        :live_data_set_size      => md[:live_data_set_size].to_i,
        :response_code           => md[:response_code].to_i
      }.delete_if{|k,v| v == 0}
    end

    # /!\ FAILSAFE /!\  Wed Sep 15 16:49:43 +0200 2010  Status: 500
    FAILSAFE = lambda do |line|
      line =~ %r{/!\\ FAILSAFE /!\\.*(?:Status: (\d+))} and {:response_code => ($1||500).to_i}
    end

    # default routing key matcher
    ROUTING_KEY_MATCHER = lambda do |key|
       key =~ /^logs\.(.+?)\.(.+?)\..+$/ and {:app => $1, :env => $2}
    end

    # default routing key matcher
    XING_ROUTING_KEY_MATCHER = lambda do |key|
       key =~ /^logs\.([^.]+)(?:\..+)?$/ and { :app => $1, :env => "production" }
    end

  end

end

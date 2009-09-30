require File.expand_path(File.dirname(__FILE__)+'/../test_helper')

class MatcherTest < ActiveSupport::TestCase
  test "xing session information can be extracted from log line for new sessions" do
    session_id = "e57067d41a53522af461de8344ca840d"
    log_line = "Session ID: #{session_id} (X)"
    expected = {:session_id => session_id, :new_session => 0}
    assert_equal expected, Matchers::SESSION_XING.call(log_line)
  end

  test "xing session information can be extracted from log line for existing sessions" do
    session_id = "e57067d41a53522af461de8344ca840d"
    log_line = "Session ID: #{session_id} (N)"
    expected = {:session_id => session_id, :new_session => 1}
    assert_equal expected, Matchers::SESSION_XING.call(log_line)
  end

  test "processing line can be matched" do
    page = "TestController::index"
    ip = "127.0.0.1"
    started_at = "2009-09-26 16:25:17"
    log_line = "Processing #{page} (for #{ip} at #{started_at})"
    expected = {:page => page, :ip => ip, :started_at => started_at}
    assert_equal expected, Matchers::PROCESSING.call(log_line)
  end

  test "rails default completed line can be matched" do
    log_line = "Completed in 883ms (View: 201, DB: 459) | 200 OK [http://localhost/]"
    expected = {:total_time => 883.0, :view_time => 201.0, :db_time => 459.0, :response_code => 200}
    assert_equal expected, Matchers::COMPLETED_RAILS.call(log_line)
  end

  test "old xing completed line can be matched" do
    log_line = "Completed in 277.752ms (View: 15.616, DB: 0.000(0), API: 0.000(0), SR: 0.000(0), MC: 1.916(4r,0m), GC: 238.353(1)) | 200 OK"
    expected = {:response_code=>200,
     :allocated_objects=>0,
     :gc_time=>238.353,
     :search_time=>0.0,
     :gc_calls=>1,
     :search_calls=>0,
     :total_time=>277.752,
     :heap_growth=>0,
     :db_calls=>0,
     :memcache_time=>1.916,
     :heap_size=>0,
     :db_sql_query_cache_hits=>0,
     :memcache_calls=>4,
     :view_time=>15.616,
     :allocated_bytes=>0,
     :api_time=>0.0,
     :memcache_misses=>0,
     :db_time=>0.0,
     :api_calls=>0}
    assert_equal(expected, Matchers::COMPLETED_XING.call(log_line))
  end
  
  test "latest xing default completed line can be matched" do
    log_line = "Completed in 399.006ms (View: 77.092, DB: 116.799(3,0), API: 75.103(2), SR: 0.000(0), MC: 4.778(2r,0m), GC: 0.000(0), HP: 0(1500000,116520,3449839)) | 200 OK [http://nowhere.org/hey]"
    expected = {
      :total_time=>399.006,
      :view_time=>77.092,
      :db_time=>116.799,
      :db_calls=>3,
      :db_sql_query_cache_hits=>0,
      :api_time=>75.103,
      :api_calls=>2,
      :search_time=>0.0,
      :search_calls=>0,
      :memcache_time=>4.778,
      :memcache_calls=>2,
      :memcache_misses=>0,
      :gc_time=>0.0,
      :gc_calls=>0,
      :heap_growth=>0,
      :heap_size=>1500000,
      :allocated_objects=>116520,
      :allocated_bytes=>3449839,
      :response_code=>200}
    assert_equal expected, Matchers::COMPLETED_XING.call(log_line)
  end

  test "log line can be recognized (xing format)" do
    log_line = "Aug 31 06:05:52 localhost rails[15019] user[Anonymous]: DADADA"
    expected = ["localhost", "15019", "Anonymous", "DADADA"]
    assert_equal expected, Matchers::LOG_LINE_SPLITTER.call(log_line)
  end

  test "log line can be recognized (syslog format)" do
    log_line = "Aug 31 06:05:52 localhost rails[15019]: DADADA"
    expected = ["localhost", "15019", nil, "DADADA"]
    assert_equal expected, Matchers::LOG_LINE_SPLITTER.call(log_line)
  end
end

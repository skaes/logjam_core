require File.expand_path(File.dirname(__FILE__)+'/../test_helper')

class RequestInfoTest < ActiveSupport::TestCase
  test "other time should be total_time minus the sum of the other times" do
    processing_line = "Processing Goofy::index (for 127.0.0.1 at 2009-07-26 06:00:50)"
    completed_line = "Completed in 409.497ms (View: 225.796, DB: 19.851(6), API: 94.776(3), SR: 7.409(1), MC: 17.189(3r,0m), GC: 190.873(1)) | 200 OK"
    lines = [processing_line, completed_line]

    info = RequestInfo.new 'localhost', 1001, 42, lines
    expected = {
     :search_time=>7.409,
     :allocated_objects=>0,
     :user_id=>42,
     :minute5=>72,
     :other_time=>44.4760000000001,
     :memcache_calls=>3,
     :minute2=>180,
     :minute1=>360,
     :gc_calls=>1,
     :api_calls=>3,
     :db_calls=>6,
     :started_at=>"2009-07-26 06:00:50",
     :api_time=>94.776,
     :host=>"localhost",
     :response_code=>200,
     :ip=>"127.0.0.1",
     :allocated_bytes=>0,
     :heap_size=>0,
     :search_calls=>1,
     :gc_time=>190.873,
     :memcache_time=>17.189,
     :db_time=>19.851,
     :db_sql_query_cache_hits=>0,
     :process_id=>1001,
     :total_time=>409.497,
     :page=>"Goofy::index",
     :heap_growth=>0,
     :view_time=>225.796,
     :memcache_misses=>0}
    expected.keys.each do |key|
      next unless ControllerAction.instance_methods.include? key
      if expected[key].is_a? Float
        assert_in_delta(expected[key], info.to_hash[key], 0.001)
      else
        assert_equal expected[key], info.to_hash[key]
      end
    end
  end
end

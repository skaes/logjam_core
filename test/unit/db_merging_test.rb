require_relative "../test_helper"

class DbMergingTest < ActiveSupport::TestCase
  ATOTAL = {
        "_id" => "59879160cf4f6565e5ac1429",
        "page" => "Foobar::BazController#index",
        "count" => 131705,
        "gc_time" => 547775.471134064,
        "gc_time_sq" => 3693346.760637327,
        "other_time" => 1277613.0270670517,
        "other_time_sq" => 14558677.57164119,
        "rest_time" => 22849288.35185801,
        "rest_time_sq" => 28775036120.224606,
        "total_time" => 25824023.401989795,
        "total_time_sq" => 30923610913.95561,
        "view_time" => 1258995.5416049464,
        "view_time_sq" => 33051080.65797762,
        "wait_time" => 345238.2870409248,
        "wait_time_sq" => 1335759236.9889393,
        "rest_calls" => 1320004,
        "rest_calls_sq" => 15515588,
        "rest_queue_runs" => 463550,
        "rest_queue_runs_sq" => 1719456,
        "allocated_bytes" => 279115091216,
        "allocated_bytes_sq" => 1105185776398035200,
        "allocated_memory" => 454283578496,
        "allocated_memory_sq" => 2629274073088860700,
        "allocated_objects" => 4379212182,
        "allocated_objects_sq" => 207558224879594,
        "heap_size" => 137968899336,
        "heap_size_sq" => 145608612468893000,
        "live_data_set_size" => 65250818406,
        "live_data_set_size_sq" => 33435060381052212,
        "apdex" => {
                "satisfied" => 125356,
                "happy" => 49714,
                "tolerating" => 5499,
                "frustrated" => 850
        },
        "response" => {
                "200" => 122860,
                "304" => 7992,
                "302" => 733,
                "500" => 92,
                "401" => 28
        },
        "severity" => {
                "1" => 131590,
                "4" => 92,
                "2" => 23
        },
        "gc_time_max" => 48.39352100006491,
        "other_time_max" => 319.6258278272524,
        "rest_time_max" => 10049.474194,
        "total_time_max" => 11646.327340680298,
        "view_time_max" => 391.16487465798855,
        "wait_time_max" => 11528.614457680298,
        "rest_calls_max" => 18,
        "rest_queue_runs_max" => 7,
        "allocated_bytes_max" => 39444488,
        "allocated_memory_max" => 54194288,
        "allocated_objects_max" => 368745,
        "heap_size_max" => 1787856,
        "live_data_set_size_max" => 1018277,
        "ajax_count" => 78812,
        "frontend_count" => 114747,
        "ajax_time" => 31320897,
        "ajax_time_sq" => 46537370423,
        "frontend_time" => 80379670,
        "frontend_time_sq" => 253428235730,
        "fapdex" => {
                "happy" => 70226,
                "satisfied" => 108559,
                "frustrated" => 562,
                "tolerating" => 5626
        },
        "xapdex" => {
                "happy" => 66044,
                "satisfied" => 77518,
                "tolerating" => 1156,
                "frustrated" => 138
        },
        "ajax_time_max" => 21805,
        "frontend_time_max" => 59882,
        "db_time" => 92888.19441900023,
        "db_time_sq" => 589462.3540264098,
        "db_calls" => 83417,
        "db_calls_sq" => 154571,
        "gc_calls" => 8054,
        "gc_calls_sq" => 8054,
        "db_time_max" => 353.898265,
        "db_calls_max" => 2,
        "gc_calls_max" => 1,
        "page_count" => 35935,
        "connect_time" => 1287999,
        "connect_time_sq" => 2733065769,
        "dom_interactive" => 31866804,
        "dom_interactive_sq" => 81084339970,
        "load_time" => 114949,
        "load_time_sq" => 12616525,
        "navigation_time" => 7382287,
        "navigation_time_sq" => 20826332525,
        "page_time" => 49058773,
        "page_time_sq" => 206890865307,
        "processing_time" => 32155198,
        "processing_time_sq" => 107316686874,
        "request_time" => 4914247,
        "request_time_sq" => 2677463061,
        "response_time" => 3208512,
        "response_time_sq" => 2040492458,
        "html_nodes" => 10839585,
        "html_nodes_sq" => 3309750935,
        "script_nodes" => 538646,
        "script_nodes_sq" => 8087488,
        "style_nodes" => 108561,
        "style_nodes_sq" => 330223,
        "papdex" => {
                "satisfied" => 31041,
                "happy" => 4182,
                "frustrated" => 424,
                "tolerating" => 4470
        },
        "connect_time_max" => 34242,
        "dom_interactive_max" => 50651,
        "load_time_max" => 2614,
        "navigation_time_max" => 51153,
        "page_time_max" => 59882,
        "processing_time_max" => 54626,
        "request_time_max" => 15291,
        "response_time_max" => 14192,
        "html_nodes_max" => 982,
        "script_nodes_max" => 25,
        "style_nodes_max" => 11,
        "js_exceptions" => {
                "Expected identifier, string or number" => 1,
                "ReferenceError: s is not defined" => 3,
        },
        "exceptions" => {
                "RESTApi::CurlTimeout" => 91,
                "ActionView::Template::Error" => 91,
                "RESTApi::CurlError" => 1
        },
        "heap_growth" => 690744,
        "heap_growth_sq" => 19702845504,
        "heap_growth_max" => 51000,
        "soft_exceptions" => {
                "RESTApi::Request::NetworkTimeLoss" => 23,
                "RESTApi::InternalServerError" => 5,
                "RESTApi::CurlError" => 3
        },
        "senders" => {
                "A::B#xxx_deleted" => 137
        },
        "callers" => {
                "X::Y#z" => 2
        },
  }

  def convert_pair(key, val)
    case val
    when Float, Integer
      { key => val }
    when Hash
      val.each_with_object({}) do |(k,v), h|
        h.merge!(convert_pair("#{key}.#{k}", v))
      end
    else
      raise "unexpected value for key #{key}: #{v.class}(#{v.inspect})"
    end
  end

  def to_upsert(hash, keys: %w(_id page))
    selector = hash.slice(*keys).except("_id")

    flat_hash = {}
    hash.except(*keys).each do |k,v|
      flat_hash.merge!( convert_pair(k,v) )
    end
    incs = flat_hash.select{|k,_| k !~ /_max\z/}
    maxs = flat_hash.select{|k,_| k =~ /_max\z/}
    {:selector => selector, :incs => incs, :maxs => maxs}
  end

  test "total can be converted to maxs and increments" do
    hash = to_upsert(ATOTAL)
    assert_equal({"page"=>"Foobar::BazController#index"}, hash[:selector])
    assert_equal({"count"=>131705, "gc_time"=>547775.471134064, "gc_time_sq"=>3693346.760637327, "other_time"=>1277613.0270670517, "other_time_sq"=>14558677.57164119, "rest_time"=>22849288.35185801, "rest_time_sq"=>28775036120.224606, "total_time"=>25824023.401989795, "total_time_sq"=>30923610913.95561, "view_time"=>1258995.5416049464, "view_time_sq"=>33051080.65797762, "wait_time"=>345238.2870409248, "wait_time_sq"=>1335759236.9889393, "rest_calls"=>1320004, "rest_calls_sq"=>15515588, "rest_queue_runs"=>463550, "rest_queue_runs_sq"=>1719456, "allocated_bytes"=>279115091216, "allocated_bytes_sq"=>1105185776398035200, "allocated_memory"=>454283578496, "allocated_memory_sq"=>2629274073088860700, "allocated_objects"=>4379212182, "allocated_objects_sq"=>207558224879594, "heap_size"=>137968899336, "heap_size_sq"=>145608612468893000, "live_data_set_size"=>65250818406, "live_data_set_size_sq"=>33435060381052212, "apdex.satisfied"=>125356, "apdex.happy"=>49714, "apdex.tolerating"=>5499, "apdex.frustrated"=>850, "response.200"=>122860, "response.304"=>7992, "response.302"=>733, "response.500"=>92, "response.401"=>28, "severity.1"=>131590, "severity.4"=>92, "severity.2"=>23, "ajax_count"=>78812, "frontend_count"=>114747, "ajax_time"=>31320897, "ajax_time_sq"=>46537370423, "frontend_time"=>80379670, "frontend_time_sq"=>253428235730, "fapdex.happy"=>70226, "fapdex.satisfied"=>108559, "fapdex.frustrated"=>562, "fapdex.tolerating"=>5626, "xapdex.happy"=>66044, "xapdex.satisfied"=>77518, "xapdex.tolerating"=>1156, "xapdex.frustrated"=>138, "db_time"=>92888.19441900023, "db_time_sq"=>589462.3540264098, "db_calls"=>83417, "db_calls_sq"=>154571, "gc_calls"=>8054, "gc_calls_sq"=>8054, "page_count"=>35935, "connect_time"=>1287999, "connect_time_sq"=>2733065769, "dom_interactive"=>31866804, "dom_interactive_sq"=>81084339970, "load_time"=>114949, "load_time_sq"=>12616525, "navigation_time"=>7382287, "navigation_time_sq"=>20826332525, "page_time"=>49058773, "page_time_sq"=>206890865307, "processing_time"=>32155198, "processing_time_sq"=>107316686874, "request_time"=>4914247, "request_time_sq"=>2677463061, "response_time"=>3208512, "response_time_sq"=>2040492458, "html_nodes"=>10839585, "html_nodes_sq"=>3309750935, "script_nodes"=>538646, "script_nodes_sq"=>8087488, "style_nodes"=>108561, "style_nodes_sq"=>330223, "papdex.satisfied"=>31041, "papdex.happy"=>4182, "papdex.frustrated"=>424, "papdex.tolerating"=>4470, "js_exceptions.Expected identifier, string or number"=>1, "js_exceptions.ReferenceError: s is not defined"=>3, "exceptions.RESTApi::CurlTimeout"=>91, "exceptions.ActionView::Template::Error"=>91, "exceptions.RESTApi::CurlError"=>1, "heap_growth"=>690744, "heap_growth_sq"=>19702845504, "soft_exceptions.RESTApi::Request::NetworkTimeLoss"=>23, "soft_exceptions.RESTApi::InternalServerError"=>5, "soft_exceptions.RESTApi::CurlError"=>3, "senders.A::B#xxx_deleted"=>137, "callers.X::Y#z"=>2}, hash[:incs])
    assert_equal({"gc_time_max"=>48.39352100006491, "other_time_max"=>319.6258278272524, "rest_time_max"=>10049.474194, "total_time_max"=>11646.327340680298, "view_time_max"=>391.16487465798855, "wait_time_max"=>11528.614457680298, "rest_calls_max"=>18, "rest_queue_runs_max"=>7, "allocated_bytes_max"=>39444488, "allocated_memory_max"=>54194288, "allocated_objects_max"=>368745, "heap_size_max"=>1787856, "live_data_set_size_max"=>1018277, "ajax_time_max"=>21805, "frontend_time_max"=>59882, "db_time_max"=>353.898265, "db_calls_max"=>2, "gc_calls_max"=>1, "connect_time_max"=>34242, "dom_interactive_max"=>50651, "load_time_max"=>2614, "navigation_time_max"=>51153, "page_time_max"=>59882, "processing_time_max"=>54626, "request_time_max"=>15291, "response_time_max"=>14192, "html_nodes_max"=>982, "script_nodes_max"=>25, "style_nodes_max"=>11, "heap_growth_max"=>51000}, hash[:maxs])
  end

end

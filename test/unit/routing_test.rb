require_relative "../test_helper"

class RoutingTestTest < ActionDispatch::IntegrationTest
  test "routing" do
    assert_generates "/2001/11/01", :controller => "logjam/logjam", :action => "index", :year => "2001", :month => "11", :day => "01"
    assert_generates "/2001/11/01/show/abcde", :controller => "logjam/logjam", :action => "show", :id => "abcde", :year => "2001", :month => "11", :day => "01"
  end
end

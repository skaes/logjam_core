require_relative  '../test_helper'

class LogjamControllerTest < ActionDispatch::IntegrationTest
  def prefixed(path)
    "/" + Date.today.iso8601.gsub('-', '/') + path
  end

  test "root url gets redirected to index for current day" do
    get "/"
    assert_redirected_to prefixed("?app=logjam&default_app=logjam&default_env=test&env=test&page=")
  end

  test "showing the index page" do
    get prefixed("?page=")
    assert_response :success
    assert_match(/Shiver me timbers!/, response.body)
  end
end

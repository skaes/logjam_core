require_relative  '../test_helper'

class LogjamControllerTest < ActionDispatch::IntegrationTest
  def prefixed(path)
    "/" + Date.today.iso8601.gsub('-', '/') + path
  end

  test "root url gets redirected to index for current day" do
    get "/"
    assert_redirected_to prefixed("?app=logjam&env=test&page=")
  end

  test "showing the index page" do
    get prefixed("?page=")
    assert_response :success
    assert_match(/No data found for application/, response.body)
  end
end

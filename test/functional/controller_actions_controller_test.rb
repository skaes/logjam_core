require File.expand_path(File.join(File.dirname(__FILE__), '/../test_helper'))
load File.expand_path(File.join(File.dirname(__FILE__), '/../yesterday.rb'))

class TimingActionsTest < ActionController::TestCase
  tests ControllerActionsController

  def setup
    Factory.create(:yesterday, :total_time => 10, :view_time => 10)
  end

  test "should get index" do
    get :index
    assert_response :success
  end

  test "should get request_time_distribution" do
    # with only one datapoint we get gnuplot warnings about empty xrange and yrange
    Factory.create(:yesterday, :total_time => 20, :db_time => 11, :view_time => 9)
    get :request_time_distribution
    assert_response :success
  end
end

if Resource.memory_resources.any?
  class MemoryActionsTest < ActionController::TestCase
    tests ControllerActionsController
  
    def setup
      Factory.create(:yesterday, :allocated_bytes => 1024, :allocated_objects => 1024, :heap_size => 1024)
    end

    test "should get allocated_objects_distribution" do
      # avoiding warnings about empty xrange and yrange
      Factory.create(:yesterday, :allocated_bytes => 2048, :allocated_objects => 2048, :heap_size => 2048)
      Factory.create(:yesterday, :allocated_bytes => 2048, :allocated_objects => 2048, :heap_size => 2048)
      get :allocated_objects_distribution
      assert_response :success
    end

    test "should get allocated_size_distribution" do
      # avoiding warnings about empty xrange and yrange
      Factory.create(:yesterday, :allocated_bytes => 2048, :allocated_objects => 2048, :heap_size => 2048)
      Factory.create(:yesterday, :allocated_bytes => 2048, :allocated_objects => 2048, :heap_size => 2048)
      get :allocated_size_distribution
      assert_response :success
    end
  end
end

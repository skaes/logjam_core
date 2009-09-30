require 'test_helper'
load 'yesterday.rb'

class BasicFilteredDatasetTest < ActiveSupport::TestCase
  def setup
    @dataset = FilteredDataset.new(:class => Yesterday)
  end
  
  test "with no data, empty? should return true" do
    assert @dataset.empty?
  end

  test "count_requests should return the number of controller_action objects" do
    Factory.create(:yesterday)
    Factory.create(:yesterday)
    assert_equal 2, @dataset.count_requests
  end

  test "count_distinct_users should count the same user only once" do
    Factory.create(:yesterday, :user_id => 42)
    Factory.create(:yesterday, :user_id => 42)
    assert_equal 1, @dataset.count_distinct_users
  end

  test "sum should sum the total_time values" do
    Factory.create(:yesterday, :total_time => 2.0)
    Factory.create(:yesterday, :total_time => 3.0)
    assert_equal 5.0, @dataset.sum
  end
end

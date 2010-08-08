require 'test_helper'
load 'yesterday.rb'

class FilteringTheFilteredDatasetTest < ActiveSupport::TestCase
  test "setting response_code should filter the dataset" do
    Factory.create(:yesterday, :response_code => 200)
    Factory.create(:yesterday, :response_code => 500)
    dataset = FilteredDataset.new(:class => Yesterday, :response_code => 500)
    assert_equal 1, dataset.count_requests
  end

  test "setting page should filter the dataset" do
    Factory.create(:yesterday, :page => 'ha ha')
    Factory.create(:yesterday, :page => 'find me')
    dataset = FilteredDataset.new(:class => Yesterday, :page => 'find me')
    assert_equal 1, dataset.count_requests
  end
  
  test "combining conditions should work" do
    Factory.create(:yesterday, :response_code => 500, :page => 'expected')
    Factory.create(:yesterday, :response_code => 500, :page => 'surprise')
    dataset = FilteredDataset.new(:class => Yesterday, :response_code => 500, :page => 'surprise')
    assert_equal 1, dataset.count_requests
  end
end

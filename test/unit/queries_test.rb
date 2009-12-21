require 'test_helper'
load 'yesterday.rb'

class SlowestPagesVSMostTimeConsumingTest < ActiveSupport::TestCase
  def setup
    3.times { Factory.create(:yesterday, :page => '3 * 10', :total_time => 10) }
    2.times { Factory.create(:yesterday, :page => '2 * 12', :total_time => 12) }
  end

  test "slowest pages: most time on average" do
    dataset = FilteredDataset.new(:class => Yesterday, :resource => :total_time, :grouping => :page, :grouping_function => :avg)
    assert_equal ['2 * 12', '3 * 10'], dataset.do_the_query.map {|p| p.page}
  end

  test "most time consuming pages: most time in total, added up across all requests" do
    dataset = FilteredDataset.new(:class => Yesterday, :resource => :total_time, :grouping => :page, :grouping_function => :sum)
    assert_equal ['3 * 10', '2 * 12'], dataset.do_the_query.map {|p| p.page}
  end
end

class InterestingQueriesWithFilteredDatasetsTest < ActiveSupport::TestCase
  test "most frequently requested pages" do
    2.times { |t| Factory.create(:yesterday, :page => 'popular') }
    1.times { |t| Factory.create(:yesterday, :page => 'unpopular') }
    dataset = FilteredDataset.new(:class => Yesterday, :resource => '1', :grouping => :page, :grouping_function => :sum)
    assert_equal ['popular', 'unpopular'], dataset.do_the_query.map {|p| p.page}
  end

  if Resource.memory_resources.any?
    test "object allocation pigs" do
      Factory.create(:yesterday, :page => 'very piggish', :allocated_objects => 1000)
      Factory.create(:yesterday, :page => 'not piggish', :allocated_objects => 0)
      dataset = FilteredDataset.new(:class => Yesterday, :resource => :allocated_objects, :grouping => :page, :grouping_function => :avg)
      assert_equal ['very piggish', 'not piggish'], dataset.do_the_query.map {|p| p.page}
    end

    test "malloc pigs" do
      Factory.create(:yesterday, :page => 'very piggish', :allocated_bytes => 1000)
      Factory.create(:yesterday, :page => 'not piggish', :allocated_bytes => 0)
      dataset = FilteredDataset.new(:class => Yesterday, :resource => :allocated_bytes, :grouping => :page, :grouping_function => :avg)
      assert_equal ['very piggish', 'not piggish'], dataset.do_the_query.map {|p| p.page}
    end

    test "average total memory by quintile" do
      [1,2,3,4,5].each { |i| Factory.create(:yesterday, :allocated_memory => 1024 * i) }
      dataset = FilteredDataset.new(:class => Yesterday)
      quintiles = [1,2,3,4,5].map{|i| dataset.average_total_memory_by_quintile(i)}
      assert_equal [1,2,3,4,5].map{|i| 1024 * i}, quintiles.map{|q| q.to_f}
    end
  end

  test "worst user experience" do
    Factory.create(:yesterday, :user_id => 333, :page => 'really slow', :total_time => 1000)
    20.times { Factory.create(:yesterday, :user_id => 222, :page => 'slow', :total_time => 100) }
    20.times { Factory.create(:yesterday, :user_id => 111, :page => 'fast', :total_time => 1) }
    dataset = FilteredDataset.new(:class => Yesterday, :resource => :total_time, :grouping => :user_id, :grouping_function => :avg)
    assert_equal [333, 222, 111], dataset.do_the_query.map {|worst| worst.user_id}
  end
  
  test "average total time by quintile" do
    [1,2,3,4,5].each { |i| Factory.create(:yesterday, :total_time => i) }
    dataset = FilteredDataset.new(:class => Yesterday)
    quintiles = [1,2,3,4,5].map{|i| dataset.average_total_time_by_quintile(i)}
    assert_equal [1,2,3,4,5].map{|i| i.to_s}, quintiles
  end

end

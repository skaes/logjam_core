require 'test_helper'
load 'yesterday.rb'

class StatisticsTest < ActiveSupport::TestCase
  test "timing statistics keys" do
    timing = FilteredDataset.new(:class => Yesterday).statistics(:time)
    expected = Resource.time_resources.map{|r| "avg_#{r}"} + Resource.time_resources.map{|r| "std_#{r}"}
    assert_equal expected.sort, timing.keys.sort
  end

  test "timing statistics values" do
    10.times { |i| Factory.create(:yesterday, :total_time => 10, :db_time => i, :view_time => 10-i) }
    timing = FilteredDataset.new(:class => Yesterday).statistics(:time)
    assert_equal '4.5', timing['avg_db_time']
    assert_equal '5.5', timing['avg_view_time']
    assert_equal '10', timing['avg_total_time']
    assert_not_equal '0', timing['std_db_time']
    assert_not_equal '0', timing['std_view_time']
    assert_equal '0', timing['std_total_time']
  end

  test "memory statistics keys" do
    return if Resource.memory_resources.empty?
    memory = FilteredDataset.new(:class => Yesterday).statistics(:memory)
    expected = Resource.memory_resources.map{|r| "avg_#{r}"} + Resource.memory_resources.map{|r| "std_#{r}"}
    assert_equal expected.sort, memory.keys.sort
  end

  test "memory statistics values should be measured in units of bytes" do
    return if Resource.memory_resources.empty?
    Factory.create(:yesterday, :allocated_memory => 40*1024+1024, :allocated_objects => 1024, :allocated_bytes => 1024, :heap_size => 1024)
    memory = FilteredDataset.new(:class => Yesterday).statistics(:memory)
    keys = %w(avg_allocated_bytes avg_allocated_memory avg_allocated_objects avg_heap_size
              std_allocated_bytes std_allocated_memory std_allocated_objects std_heap_size)
    actual = memory.values_at(*keys).map(&:to_f)
    expected = [1024, 40*1024+1024, 40 * 1024, 40* 1024, 0, 0, 0, 0]
    assert_equal expected, actual
  end
end

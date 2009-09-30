require 'test_helper'
load 'yesterday.rb'

class LogDataTest < ActiveSupport::TestCase
  test 'log_data_dates should be empty when all the tables are empty' do
    assert_equal [], ControllerAction.log_data_dates
  end

  test 'log_data_dates should include yesterday' do
    Factory.create(:yesterday)
    assert_equal [Yesterday.date.to_s(:db)[0..9]], ControllerAction.log_data_dates
  end
end

class ClassForDateTest < ActiveSupport::TestCase
  def setup
    ControllerAction.expects(:ensure_table_exists).with('1958-07-19')
    ControllerAction.class_for_date('1958-07-19')
  end

  test 'class_for_date should create a class' do
    assert defined? ControllerAction_1958_07_19
  end

  test 'class_for_date should create a class with a date method' do
    assert_equal '1958-07-19 00:00:00', ControllerAction_1958_07_19.date.to_s(:db)
  end

  test 'class_for_date should create a class with a table_name method' do
    assert_equal 'log_data_1958_07_19', ControllerAction_1958_07_19.table_name
  end
end

class SanitizeDateTest < ActiveSupport::TestCase
  test 'sanitize date should convert - to _' do
    assert_equal '1958_07_19', ControllerAction.sanitize_date(Time.parse('1958-07-19'))
  end

  test 'sanitize date should work with Date objects' do
    assert_equal '1958_07_19', ControllerAction.sanitize_date(Date.parse('1958-07-19'))
  end

  test 'sanitize date should work with DateTime objects' do
    assert_equal '1958_07_19', ControllerAction.sanitize_date(DateTime.parse('1958-07-19'))
  end

  test 'sanitize date should work with strings' do
    assert_equal '1958_07_19', ControllerAction.sanitize_date('1958-07-19')
  end
  
  test 'sanitize date raises when confused' do
    assert_raises(RuntimeError) {ControllerAction.sanitize_date('1958/07/19')}
  end
end


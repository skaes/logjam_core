require_relative "../test_helper"

class ModuleExtractionTest < ActiveSupport::TestCase
  include Logjam::Helpers

  test "action is a normal controller action" do
    @page, @module = convert_action_to_page_and_module("A#x", {})
    assert_equal "A#x", @page
    assert_equal "::A", @module
  end

  test "action is a controller action in a module" do
    @page, @module = convert_action_to_page_and_module("A::B#x", {})
    assert_equal "A::B#x", @page
    assert_equal "::A", @module
  end

  test "action is a controller action in a module in a module" do
    @page, @module = convert_action_to_page_and_module("A::B::C#x", {})
    assert_equal "A::B::C#x", @page
    assert_equal "::A", @module
  end

  test "action is nil" do
    @page, @module = convert_action_to_page_and_module(nil, {})
    assert_unknown
  end

  test "action is empty string" do
    @page, @module = convert_action_to_page_and_module("", {})
    assert_unknown
  end

  test "action is blank string" do
    @page, @module = convert_action_to_page_and_module("  ", {})
    assert_unknown
  end

  test "action is a single hash sign" do
    @page, @module = convert_action_to_page_and_module("#", {})
    assert_unknown
  end

  test "action is a single module separator" do
    @page, @module = convert_action_to_page_and_module("::", {})
    assert_unknown
  end

  test "action has a trailing hash" do
    @page, @module = convert_action_to_page_and_module("A#", {})
    assert_equal "A#unknown_method", @page
    assert_equal "::A", @module
  end

  test "action starts with a hash" do
    @page, @module = convert_action_to_page_and_module("#x", {})
    assert_equal "Unknown#x", @page
    assert_equal "::Unknown", @module
  end

  test "action has repeated hashes" do
    @page, @module = convert_action_to_page_and_module("A#####x", {})
    assert_equal "A#x", @page
    assert_equal "::A", @module
  end

  test "action has repeated colons" do
    @page, @module = convert_action_to_page_and_module("A::::B#x", {})
    assert_equal "A::B#x", @page
    assert_equal "::A", @module
  end

  test "action starts with module separator" do
    @page, @module = convert_action_to_page_and_module("::A::B#x", {})
    assert_equal "A::B#x", @page
    assert_equal "::A", @module
  end

  test "action is utter garbage" do
    @page, @module = convert_action_to_page_and_module("#:A##::B#x", {})
    assert_equal "Unknown#::A#::B#x", @page
    assert_equal "::Unknown", @module
  end

  private
  def assert_unknown
    assert_equal "Unknown#unknown_method", @page
    assert_equal "::Unknown", @module
  end
end

ENV["RAILS_ENV"] = "test"
require File.expand_path(File.dirname(__FILE__) + "/../../../config/environment")

require 'rails/test_help'

Logjam.module_eval do
  # remove all declared streams
  streams.clear
  # add one test db
  stream "logjam-test"
  # delete any existing test database
  drop_all_databases(app: "logjam", env: "test")
  # create a test database
  [ Date.today, "logjam", "test" ].tap do |p|
    db(*p)
    ensure_known_database(db_name(*p))
  end
end

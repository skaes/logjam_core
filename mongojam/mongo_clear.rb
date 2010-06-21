#!/usr/bin/env ruby

require 'rubygems'
require 'mongo'

conn = Mongo::Connection.new
conn.drop_database("logjam")

# db = conn.db("logjam")

# stats = db["log_stats"]
# stats.remove

# totals = db["totals"]
# totals.remove

# requests = db["requests"]
# requests.remove

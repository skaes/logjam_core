require 'mongo'
MONGODB = Mongo::Connection.new(ENV['MONGOJAM_HOST']||"localhost")

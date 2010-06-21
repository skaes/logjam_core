require 'rubygems'
require 'mongo'
require 'benchmark'

conn = Mongo::Connection.new
db = conn.db("mydb")
coll = db["test"]

# time = Benchmark.realtime do
#   1_000_000.times do
#     coll.insert(:time => rand())
#   end
# end
# puts "insertion time: #{time} seconds"

puts coll.count

map_f = <<-MAP
  function() {
     var t = this.time;
     emit('time', t);
     emit('squares', t*t);
     emit('count', 1);
     emit('min', t);
     emit('max', t);
  }
MAP

reduce_f = <<-REDUCE
  function(k,vs) {
    switch (k) {
    case 'min':
      var min = vs[0];
      for(var i in vs) {
        if (vs[i] < min) { min = vs[i]; }
      }
      return min;
    case 'max':
      var max = 0;
      for(var i in vs) {
        if (vs[i] > max) { max = vs[i]; }
      }
      return max;
    default:
      var sum = 0;
      for(var i in vs) sum += vs[i];
      return sum;
    }
  }
REDUCE

time = Benchmark.realtime do
  result_set = coll.map_reduce(map_f, reduce_f)
  result_hash = {}
  result_set.find.each do |row|
    result_hash[row["_id"].to_sym] = row["value"]
  end
  avg = result_hash[:avg] = result_hash[:time]/result_hash[:count]
  n = result_hash[:count]
  sum_squares = result_hash[:squares]
  result_hash[:std_dev] = Math.sqrt((sum_squares - n*avg*avg)/(n-1))
  puts result_hash.inspect
end

puts "mapreduce time: #{time} seconds"

# time = Benchmark.realtime do
#  coll.remove({})
# end
# puts "deletion time: #{time} seconds"


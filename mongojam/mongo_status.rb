require 'rubygems'
require 'benchmark'
require 'set'
require File.expand_path('../config/initializers/mongo')

db = MONGODB.db("logjam")
minutes = db["minutes"]
totals = db["totals"]
quants = db["quants"]

pages = Set.new
counts = Hash.new(0)
total_times = Hash.new(0.0)
total_times_sq = Hash.new(0.0)
averages = Hash.new(0.0)
std_devs = Hash.new(0.0)
sum_totals = Hash.new(0.0)

totals_access_time = Benchmark.realtime do

  totals.find({}).each do |row|
    page = row["page"]
    pages << page
    counts[page] += row["count"] || 0
    total_times[page] += row["total_time"] || 0.0
    total_times_sq[page] += row["total_time_sq"] || 0.0
  end

  pages.each do |page|
    begin
      count = counts[page]
      averages[page] = avg = total_times[page]/count
      sum_totals[page] += avg*count/1000.0
      std_devs[page] = std_dev = (count == 1) ? 0.0 : Math.sqrt((total_times_sq[page] - count*avg*avg)/(count-1).to_f)
    rescue
      $stderr.puts "page #{page} raised an error: #{$!}"
      $stderr.puts "count=#{count}, avg=#{avg}, std_dev=#{std_dev}"
    end
  end

end

pages.delete "all_pages"
printf "%-90s %-9s %-9s %-9s %-9s\n", "page", "count", "sum", "average", "std-deviation"
(["all_pages"]+pages.to_a.sort_by{|p| -sum_totals[p] }).each do |page|
  printf "%-90s %9d %9.2f %9.2f %9.2f\n", page, counts[page], sum_totals[page], averages[page], std_devs[page]
end

mhash = {}
mhash_access_time = Benchmark.realtime do
  minutes.find({:page => "all_pages"}, {:fields => ["minute", "total_time"]}).each do |row|
    mhash[row["minute"].to_i] = row["total_time"].to_f
  end
end
puts "minutes"
puts mhash.inspect

qhash = {}
qhash_access_time = Benchmark.realtime do
  quants.find({:page => "all_pages", :kind => "t"}, {:fields => ["quant", "total_time"]}).each do |row|
    n = row["total_time"].to_i
    q = row["quant"].to_i
    qhash[q] = n
  end
end
puts "time quants"
puts qhash.inspect

ohash = {}
ohash_access_time = Benchmark.realtime do
  quants.find({:page => "all_pages", :kind => "m"}, {:fields => ["quant", "allocated_objects"]}).each do |row|
    n = row["allocated_objects"].to_i
    q = row["quant"].to_i
    ohash[q] = n
  end
end
puts "object quants"
puts ohash.inspect


puts "time    access time: #{"%.5f" % (totals_access_time)} seconds"
puts "minutes size: #{mhash.size}"
puts "minutes access time: #{"%.5f" % (mhash_access_time)} seconds"
puts "time quants size: #{qhash.size}"
puts "time quants  access time: #{"%.5f" % (qhash_access_time)} seconds"
puts "object quants size: #{qhash.size}"
puts "object quants  access time: #{"%.5f" % (ohash_access_time)} seconds"


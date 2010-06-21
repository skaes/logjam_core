# create benchmarker instance
class BM < RailsBenchmark
  def establish_test_session(*args)
  end
  def update_test_session_data(*args)
  end
end
RAILS_BENCHMARKER = BM.new

# if your session manager isn't ActiveRecordStore, or if you don't
# want sesssions to be cleaned after benchmarking, just use
# RAILS_BENCHMARKER = RailsBenchmark.new

# create session data required to run the benchmark
# customize this code if your benchmark needs session data

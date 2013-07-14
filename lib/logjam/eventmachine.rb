require "eventmachine"

# try to force eventmachine timers to be more accurate.
# when a callback takes longer to execute than the smallest timer interval used,
# you might get surprising results.
# see http://soohwan.blogspot.de/2011/02/fix-eventmachineperiodictimer.html

module EventMachine
  class PeriodicTimer
    alias :old_initialize :initialize
    def initialize interval, callback=nil, &block
      # Added two additional instance variables to compensate difference.
      @start = Time.now
      @fixed_interval = interval
      old_initialize interval, callback, &block
    end
    alias :old_schedule :schedule
    def schedule
      # print "Started at #{@start}..: "
      compensation = (Time.now - @start) % @fixed_interval
      @interval = @fixed_interval - compensation
      # Schedule
      old_schedule
    end
  end
end

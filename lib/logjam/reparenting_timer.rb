module Logjam
  module ReparentingTimer
    def shutdown_if_reparented_to_root_process
      @reparenting_timer = EM.add_periodic_timer(1) do
        if Process.ppid == 1
          begin
            log_error "refusing to become an orphan. committing suicide."
          ensure
            exit!(1)
          end
        end
      end
    end

    def stop_reparenting_timer
      if @reparenting_timer
        @reparenting_timer.cancel
        @reparenting_timer = nil
      end
    end
  end
end

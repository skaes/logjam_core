module Logjam
  class EventProcessor

    def initialize(stream)
      @stream = stream
    end

    def process(event)
      Logjam::Events.insert(event)
    end

  end
end

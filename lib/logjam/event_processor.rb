module Logjam
  class EventProcessor

    def initialize(stream)
      @stream = stream
    end

    def process(event)
      # write to mongo
      puts "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
      p event
    end

  end
end

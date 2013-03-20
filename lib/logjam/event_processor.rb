module Logjam
  class EventProcessor

    def initialize(stream)
      @stream = stream
    end

    def process(event)
      Events.new(db(event)).insert(event)
    end

    private

    def db(event)
      Logjam.db(event["started_at"], @stream.app, @stream.env)
    end
  end
end

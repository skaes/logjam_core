module Logjam
  class EventProcessor
    include Helpers

    def initialize(stream)
      @stream = stream
    end

    def process(event)
      Events.new(db(event)).insert(event) unless Logjam.dryrun
    rescue => e
      log_error("error during processing event: #{event.inspect}")
      log_error("#{e.class}(#{e})")
    end

    private

    def db(event)
      Logjam.db(event["started_at"], @stream.app, @stream.env)
    end
  end
end

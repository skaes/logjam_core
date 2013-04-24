module Logjam
  class JsExceptionProcessor
    include Helpers

    def initialize(stream)
      @stream = stream
    end

    def process(exception)
      JsException.new(db(exception)).insert(exception)
    rescue => e
      log_error("error during processing javascript exception: #{exception.inspect}")
      log_error("#{e.class}(#{e})")
    end

    private

    def db(exception)
      Logjam.db(exception["started_at"], @stream.app, @stream.env)
    end
  end
end

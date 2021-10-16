require "logjam"

module Logjam
  BaseDir = File.expand_path('../../..', __FILE__)

  class Engine < Rails::Engine

    rake_tasks do
      load File.join(Logjam::BaseDir, "lib/logjam/tasks/logjam.rake")
    end

    # fix a bug in rack (more a brainfuck actually)
    config.to_prepare do
      ::Rack::Utils::HeaderHash.class_eval <<-_EVA_
          def [](k)
            super(@names[k] || @names[k.downcase])
          end
        _EVA_
    end

  end
end

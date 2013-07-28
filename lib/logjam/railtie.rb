require "logjam"

module Logjam
  BaseDir = File.expand_path('../../..', __FILE__)

  class Engine < Rails::Engine

    rake_tasks do
      load File.join(Logjam::BaseDir, "lib/logjam/tasks/logjam.rake")
    end

    config.autoload_once_paths << File.join(Logjam::BaseDir, "lib")

    config.to_prepare do
      ApplicationController.helper(Logjam::LogjamHelper)
    end

    config.after_initialize do
      ::ActiveSupport::Dependencies.autoload_once_paths.reject! { |p| p =~ %r{/logjam/} }
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

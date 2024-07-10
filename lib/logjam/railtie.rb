require "logjam"

module Logjam
  BaseDir = File.expand_path('../../..', __FILE__)

  class Engine < Rails::Engine

    rake_tasks do
      load File.join(Logjam::BaseDir, "lib/logjam/tasks/logjam.rake")
    end

    config.autoload_once_paths << File.join(Logjam::BaseDir, "lib")

  end
end

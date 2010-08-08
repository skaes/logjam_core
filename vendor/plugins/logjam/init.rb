config.gem 'mongo'
config.gem 'gnuplot', :source => 'http://gems.rubyforge.org'

config.to_prepare do
  ApplicationController.helper(ApplicationHelper)
  ApplicationController.helper(ResourcesHelper)
end

config.after_initialize do
  require 'digest/md5'

  ::ActiveSupport::Dependencies.load_once_paths.reject! { |p| p =~ %r{/logjam/} }
end

# fix a bug in rack (more a brainfuck actually)
config.to_prepare do
  ::Rack::Utils::HeaderHash.class_eval <<-_EVA_
      def [](k)
        super(@names[k] || @names[k.downcase])
      end
    _EVA_
end


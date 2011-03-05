require 'logjam'

config.gem 'mongo'

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

# fix a bug in ruby 1.9.2
if RUBY_VERSION == "1.9.2"
  require 'cgi'
  require 'cgi/util'
  ::CGI.class_eval <<-_BRAIN_
    def CGI::unescape(string)
      encoding = string.encoding
      string.tr('+', ' ').gsub(/((?:%[0-9a-fA-F]{2})+)/) do
        [$1.delete('%')].pack('H*').force_encoding(encoding)
      end
    end
    _BRAIN_
end

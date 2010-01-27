# See http://github.com/topfunky/hodel_3000_compliant_logger

require 'logger'
require 'English'

##
# A logger for use with logjam and other tools that expect syslog-style log output.

class Hodel3000CompliantLogger < Logger

  ##
  # Note: If you are using FastCGI you may need to hard-code the hostname here instead of using Socket.gethostname


  def format_message(severity, timestamp, progname, msg)
    # One approach for logging user_ids is to use a global variable as shown below.
    # You can use a before_filter in your application_controller to set this global variable.
    #    before_filter { |controller| $user_id = controller.session[:user_id] || 0 }

    user_id = 
      if defined?($user_id)
        " user[#{$user_id}]"
      else
        ""
      end
    "#{timestamp.strftime("%b %d %H:%M:%S")} #{hostname} rails[#{$PID}]#{user_id}: #{msg2str(msg).gsub(/\n/, '').lstrip}\n"
  end

  # original method, pre-patch for Exception handling:
  #
  # def format_message(severity, timestamp, msg, progname)
  #   "#{timestamp.strftime("%b %d %H:%M:%S")} #{Socket.gethostname.split('.').first} rails[#{$PID}]: #{progname.gsub(/\n/, '').lstrip}\n"
  # end

  private

  def hostname
    @parsed_hostname ||= Socket.gethostname.split('.').first
  end

  def msg2str(msg)
    case msg
    when ::String
      msg
    when ::Exception
      "#{ msg.message } (#{ msg.class }): " <<
      (msg.backtrace || []).join(" | ")
    else
      msg.inspect
    end
  end

end
module Logjam
  module Helpers
    def log_info(message)
      puts "LJI[#{$$}] #{message}"; $stdout.flush
    end

    def log_error(message)
      $stderr.puts "LJE[#{$$}] #{message}"; $stderr.flush
    end

    def log_warn(message)
      $stderr.puts "LJW[#{$$}] #{message}"; $stderr.flush
    end

    def log_backtrace(e)
      log_error(e.backtrace[0..9].join("\nLJE[#{$$}] "))
    end

    def extract_minute_from_iso8601(iso_string)
      60 * iso_string[11..12].to_i + iso_string[14..15].to_i
    end

    def convert_action_to_page_and_module(action, entry)
      page = action.to_s.strip

      # remove excess colons and hash signs
      page.gsub!(/:::+/,'::')
      page.gsub!(/##+/,'#')
      # make sure colons come in pairs
      page.gsub!(/([^:]|\A):([^:]|\z)/,'\1::\2')

      # ensure we have no '::' at the beginning or directly before a '#'
      page.sub!(/^::/,'')
      page.gsub!(/::#/,'#')
      page_length = page.length

      # ensure that page has the format /(XXX::)*Module#method/
      # otherwise namespace overview and stats will be borked
      if page_length == 0
        page = "Unknown#unknown_method"
      else
        # ensure there's a '#' with a non empty action name
        hash_pos = page.index("#") || -1
        if hash_pos == -1
          page << "#unknown_method"
        elsif page_length == 1
            page = "Unknown#unknown_method"
        elsif hash_pos == page_length - 1
          page << "unknown_method"
        elsif hash_pos == 0
          page.insert(0, "Unknown")
        end
      end

      # extract a top level module name (A::..., A#foo => A)
      pmodule = "::"
      if page =~ /^([^:#]+)::/ || page =~ /^([^:#]+)#/
        pmodule << $1
      else
        log_error "MODULE EXTRACTION IS BORKED: page='#{page}', action='#{action}'"
        log_error entry.inspect
        pmodule << "Unknown"
      end

      return page, pmodule
    end

  end
end

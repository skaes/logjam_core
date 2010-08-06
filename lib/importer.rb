require 'zlib'
require 'digest'

class Importer
  # The logfile being read by the Analyzer.
  attr_reader :logfile_name

  # Creates a new Importer that will read data from +logfile_name+ and store it in the database.
  def initialize(logfile_name)
    @logfile_name  = logfile_name
    @csv_files = {}
    @csv_filenames = {}
    # for testing the importer only!
    @force_import = ENV['LOG_JAM_FORCE_IMPORT'] == "1"
  end

  # Processes the log file stroring data from each LogEntry into the database.
  def process
    if logfile_already_imported? && !@force_import
      puts "cowardly refusing to import logfile #{logfile_name} twice!"
    else
      puts "importing #{logfile_name}"
      process_internal
    end
  end

  private
  def process_internal
    raise 'needs to be implemented'
  end

  def logfile_already_imported?
    raise 'needs to be implemented'
  end

  def parse_logfile
    Parser.parse logfile_io do |entry|
      hash = entry.to_hash
      yield(hash)
    end
    io.close
  end

  def logfile_io
    @io ||=
      begin
        #cmd = @logfile_name =~ /\.gz$/ ? "zegrep" : "egrep"
        #IO.popen("#{cmd} -e '#{Matchers::PRE_MATCH}' #{@logfile_name}", "rb")
        cmd = @logfile_name =~ /\.gz$/ ? "gzcat" : "cat"
        IO.popen("#{cmd} #{@logfile_name}", "rb")
      end
  end

  def md5hash
    @md5hash ||= Digest::MD5.file(@logfile_name).hexdigest
  end
end

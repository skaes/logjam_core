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
  def columns
    @columns ||= ControllerAction.columns.map(&:name).map(&:to_sym).reject{|c|c==:id}
  end

  # Processes the log file stroring data from each LogEntry into the database.
  def process
    if logfile_already_imported? && !@force_import
      puts "cowardly refusing to import logfile #{logfile_name} twice!"
    else
      puts "importing #{logfile_name}"
      create_csv_files
      import_csv_files
      create_import_record
    end
  end

  def create_csv_files
    cmd = @logfile_name =~ /\.gz$/ ? "zegrep" : "egrep"
    io = IO.popen("#{cmd} -e '#{Matchers::PRE_MATCH}' #{@logfile_name}", "rb")
    # io = @logfile_name =~ /\.gz$/ ? Zlib::GzipReader.open(@logfile_name, "rb") : File.open(@logfile_name, "rb")
    Parser.parse io do |entry|
      hash = entry.to_hash
      # puts hash.inspect
      csv_writer(hash) << hash.values_at(*columns)
    end
    close_csv_writers
    io.close
  end

  def csv_writer(hash)
    date_str = hash[:started_at][0..9]
    @csv_files[date_str] ||=
      begin
        @csv_filenames[date_str] = filename = "/tmp/logfile-#{date_str}-#{$$}.csv"
        FasterCSV.open(filename, "w")
      end
  end

  def close_csv_writers
    @csv_files.each_value{ |csv| csv.close }
  end

  def import_csv_files
    fields = columns.map(&:to_s).join(',')
    @csv_filenames.each do |date_str, filename|
      klazz = ControllerAction[date_str]
      load_data_stmt = "load data local infile '#{filename}' into table #{klazz.table_name} fields terminated by ',' (#{fields}) "
      klazz.connection.execute load_data_stmt
    end
  end

  def logfile_already_imported?
    LogfileImportRecord.find_by_md5hash(md5hash)
  end

  def create_import_record
    LogfileImportRecord.create!(:md5hash => md5hash)
  end

  def md5hash
    @md5hash ||= Digest::MD5.file(@logfile_name).hexdigest
  end
end

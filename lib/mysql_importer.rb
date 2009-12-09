class MysqlImporter < Importer

  private
  def process_internal
    create_csv_files
    import_csv_files
    create_import_record
  end

  # Processes the log file stroring data from each LogEntry into the database.
  def columns
    @columns ||= ControllerAction.columns.map(&:name).map(&:to_sym).reject{|c|c==:id}
  end

  def create_csv_files
    parse_logfile do |entry|
      csv_writer(entry) << entry.values_at(*columns)
    end
    close_csv_writers
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

end
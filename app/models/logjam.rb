module Logjam
  extend self

  def db(date)
    MONGODB.db(db_name(date))
  end

  def db_name(date)
    "logjam-#{sanitize_date(date)}"
  end

  def databases
    MONGODB.database_names.grep(/logjam-/)
  end

  def database_days
    databases.map{|t| t.sub('logjam-', '')}.sort.reverse
  end

  def sanitize_date(date_str)
    case date_str
    when Time, Date, DateTime
      date_str = date_str.to_s(:db)
    end
    raise "invalid date" unless date_str =~ /^\d\d\d\d-\d\d-\d\d/
    date_str[0..9]
  end

  def durations
    ['1', '2', '5']
  end
end

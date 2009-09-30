class CreateLogfileImportRecords < ActiveRecord::Migration
  def self.up
    create_table :logfile_import_records do |t|
      t.column :md5hash, :string
      t.column :created_at, :timestamp
    end
    add_index :logfile_import_records, :md5hash
  end

  def self.down
    drop_table :logfile_import_records
  end
end

class CreateControllerActions < ActiveRecord::Migration
  def self.up
    create_table :controller_actions, :options => "ENGINE=MyISAM" do |t|
      t.string :host, :null => false
      t.integer :process_id, :null => false
      t.integer :user_id, :null => false
      t.string :page, :null => false
      t.integer :minute1, :null => false
      t.integer :minute2, :null => false
      t.integer :minute5, :null => false
      t.timestamp :started_at, :null => false
      t.integer :response_code, :null => false
#      t.string :session_id, :null => false
#      t.boolean :new_session, :null => false
      t.float :total_time, :null => false
      t.float :view_time, :null => false
      t.float :db_time, :null => false
#      t.float :api_time, :null => false
#      t.float :search_time, :null => false
      t.float :other_time, :null => false
#      t.float :gc_time, :null => false
#      t.float :memcache_time, :null => false
      t.integer :db_calls, :null => false
      t.integer :db_sql_query_cache_hits, :null => false
#      t.integer :api_calls, :null => false
#      t.integer :memcache_calls, :null => false
#      t.integer :memcache_misses, :null => false
#      t.integer :search_calls, :null => false
#      t.integer :gc_calls, :null => false
#      t.integer :heap_size, :null => false
#      t.integer :heap_growth, :null => false
#      t.integer :allocated_objects, :null => false
#      t.integer :allocated_bytes, :null => false
#      t.integer :allocated_memory, :null => false
    end
  end

  def self.down
    drop_table :controller_actions
  end
end

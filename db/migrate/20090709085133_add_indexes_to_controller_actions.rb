class AddIndexesToControllerActions < ActiveRecord::Migration
  def self.up
    add_index :controller_actions, :page
    add_index :controller_actions, :host
    add_index :controller_actions, :response_code
    add_index :controller_actions, :user_id
    add_index :controller_actions, :minute1
    add_index :controller_actions, :minute2
    add_index :controller_actions, :minute5
    add_index :controller_actions, :total_time
    add_index :controller_actions, :other_time
    add_index :controller_actions, :view_time
    add_index :controller_actions, :db_time
    add_index :controller_actions, :api_time
    add_index :controller_actions, :search_time
    add_index :controller_actions, :memcache_time
    add_index :controller_actions, :db_calls
    add_index :controller_actions, :db_sql_query_cache_hits
    add_index :controller_actions, :api_calls
    add_index :controller_actions, :memcache_calls
    add_index :controller_actions, :memcache_misses
    add_index :controller_actions, :search_calls
    add_index :controller_actions, :gc_calls
    add_index :controller_actions, :heap_size
    add_index :controller_actions, :heap_growth
    add_index :controller_actions, :allocated_objects
    add_index :controller_actions, :allocated_bytes
    add_index :controller_actions, :allocated_memory
  end

  def self.down
    remove_index :controller_actions, :minute2
    remove_index :controller_actions, :minute5
    remove_index :controller_actions, :minute1
    remove_index :controller_actions, :user_id
    remove_index :controller_actions, :response_code
    remove_index :controller_actions, :host
    remove_index :controller_actions, :page
    remove_index :controller_actions, :total_time
    remove_index :controller_actions, :other_time
    remove_index :controller_actions, :view_time
    remove_index :controller_actions, :db_time
    remove_index :controller_actions, :api_time
    remove_index :controller_actions, :search_time
    remove_index :controller_actions, :memcache_time
    remove_index :controller_actions, :db_calls
    remove_index :controller_actions, :db_sql_query_cache_hits
    remove_index :controller_actions, :api_calls
    remove_index :controller_actions, :memcache_calls
    remove_index :controller_actions, :memcache_misses
    remove_index :controller_actions, :search_calls
    remove_index :controller_actions, :gc_calls
    remove_index :controller_actions, :heap_size
    remove_index :controller_actions, :heap_growth
    remove_index :controller_actions, :allocated_objects
    remove_index :controller_actions, :allocated_bytes
    remove_index :controller_actions, :allocated_memory
  end
end

namespace :db do
  desc "rebuild the database"
  task :rebuild => ["db:drop", "db:create", "db:migrate"]
end

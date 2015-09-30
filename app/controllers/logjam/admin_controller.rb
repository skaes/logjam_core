# -*- coding: utf-8 -*-
require 'csv'
module Logjam

  class AdminController < ApplicationController
    layout "logjam/logjam"

    def index
      get_database_info
      respond_to do |format|
        format.html do
          @sorted_database_info = sorted_database_info
        end
        format.json do
          db_info = @database_info.map{|h,n,s|{:host => h, :db => n, :size => s}}
          render :json => Oj.dump({:db_info => db_info}, :mode => :compat)
        end
        format.csv do
          str = CSV.generate(:col_sep => ';') do |csv|
            csv << %w(Host Application Enviroment Day Size)
            sorted_database_info.each do |host, db_name, size|
              app, env, date = Logjam.extract_db_params(db_name)
              csv << [host, app, env, date, size]
            end
          end
          render :text => str, :format => :csv
        end
      end
    end

    def streams
      respond_to do |format|
        format.json do
          streams = Logjam.production_streams
          render :json => Oj.dump(streams, :mode => :compat)
        end
      end
    end

    private
    def get_database_info
      @database_info = []
      @total_bytes = 0
      Logjam.connections.each do |host,conn|
        conn.list_databases.each do |db|
          size = db["sizeOnDisk"]
          @database_info << [host, db["name"], size]
          @total_bytes += size
        end
      end
      @database_info.reject!{|i| i[1] !~ /\Alogjam/}
    end

    def sorted_database_info
      @sorted_database_info = @database_info.sort_by(&:second)
    end
  end
end

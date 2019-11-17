# -*- coding: utf-8 -*-
require 'csv'
module Logjam

  class AdminController < ApplicationController
    layout "logjam/logjam"

    def index
      get_database_info
      respond_to do |format|
        format.html do
          params.permit!
          @sorted_database_info = sorted_database_info
        end
        format.json do
          db_info = @database_info.map{|h,n,s|{:host => h, :db => n, :size => s}}
          render :json => Oj.dump({:db_info => db_info})
        end
        format.csv do
          str = CSV.generate(:col_sep => ';') do |csv|
            csv << %w(Host Application Enviroment Day Size)
            sorted_database_info.each do |host, db_name, size|
              app, env, date = Logjam.extract_db_params(db_name)
              csv << [host, app, env, date, size.to_i]
            end
          end
          render :plain => str, :format => :csv
        end
      end
    end

    def streams
      respond_to do |format|
        format.json do
          streams = Logjam.production_streams
          render :json => Oj.dump(streams)
        end
      end
    end

    private
    def get_database_info
      @database_info = get_cached_database_info
      @total_bytes = @database_info.inject(0){|sum, info| info[2] + sum}
      @database_info.reject!{|i| i[1] !~ /\Alogjam/}
    end

    def get_cached_database_info
      get_info = -> (*_args) {
        info = []
        Logjam.connections.each do |host, conn|
          conn.list_databases.each do |db|
            size = db["sizeOnDisk"]
            info << [host, db["name"], size]
          end
        end
        info
      }
      if Logjam.perform_caching
        Rails.cache.fetch("logjam-database-info", expires_in: 5.minutes, &get_info)
      else
        get_info.call
      end
    end

    def sorted_database_info
      @sorted_database_info = @database_info.sort_by(&:second)
    end
  end
end

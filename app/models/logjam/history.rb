module Logjam
  class History

    def initialize(db, app, env, page)
      @db = db
      @app = app
      @env = env
      @page = page
    end

    def data
      page = @page
      page_names = Totals.new(@db).page_names
      page = /^#{page}$/ if @page =~ /\A::/ && page_names.include?(page)
      page = /^::#{page}$/ if @page !~ /\A::/ && page_names.include?("::#{page}")
      page = 'all_pages' if @page == '' || @page == '::'
      resources = %w(apdex papdex xapdex response severity exceptions soft_exceptions total_time) + Resource.all_resources
      data = get_data(page, resources)
      collected_resources = data.inject(Set.new){|s,d| s.union(d.keys)}
      resources.reject!{|r| !collected_resources.include?(r.to_sym)}
      collected_exception_names = data.inject(Set.new){|s,d| s.union(d[:exception_counts].keys)}.to_a.sort
      # logger.debug collected_exception_names.inspect
      # logger.debug data.inspect
      {
        :resources => {
          :time => Resource.time_resources.reverse & resources,
          :calls => Resource.call_resources.reverse & resources,
          :memory => Resource.memory_resources & resources,
          :heap => Resource.heap_resources & resources,
          :frontend => Resource.frontend_resources & resources,
          :dom => Resource.dom_resources & resources
        },
        :exception_names => collected_exception_names,
        :data => data
      }
    end

    private

    def get_data(page, resources)
      databases = DatabaseManager.get_cached_databases(:app => @app, :env => @env)
      data = []
      today = Date.today
      databases.each do |db_name|
        date_str = Logjam.iso_date_string(db_name)
        date = Date.parse(date_str)
        # we only show historic data, so ignore anything newer than yesterday
        next if date >= today
        db = Logjam.connection_for(db_name).use(db_name).database
        hash = { :date => date_str, :exception_counts => {} }
        data << hash
        if summary = Totals.new(db, resources, page).pages(:limit => 1).try(:first)
          # database has at least one action
          add_data_from_summary(hash, summary)
        end
      end
      add_data_for_missing_databases(data)
    end

    def add_data_from_summary(hash, summary)
      hash.merge!(
        :request_count => summary.count,
        :errors => summary.error_count,
        :warnings => summary.warning_count,
        :exceptions => summary.overall_exception_count,
        :apdex_score => summary.apdex_score(:backend),
        :exception_counts => summary.all_exceptions,
        :five_hundreds => summary.five_hundreds,
      )
      hash[:availability] = 100 - 100.0 * hash[:five_hundreds] / hash[:request_count]
      hash[:error_rate] = 100.0 * hash[:five_hundreds] / hash[:request_count]
      if (v = summary.apdex_score(:page)) && v.to_f.finite? && v>0
        hash[:papdex_score] = v
      end
      if (v = summary.apdex_score(:ajax)) && v.to_f.finite? && v>0
        hash[:xapdex_score] = v
      end
      Resource.all_resources.each do |r|
        v = summary.avg(r)
        if v > 0 && v.to_f.finite?
          hash[r.to_sym] = v
        end
      end
    end

    def add_data_for_missing_databases(data)
      return data if data.empty?
      data.sort_by!{|d| d[:date]}
      tmp = [data.shift]
      while !data.empty?
        last_date = Date.parse(tmp.last[:date])
        next_date = Date.parse(data.first[:date])
        if next_date - last_date == 1
          tmp << data.shift
        else
          tmp << { :date => (last_date+1).iso8601, :exception_counts => {} }
        end
      end
      data.replace(tmp)
    end

  end
end

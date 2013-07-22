require 'oj'

module Logjam

  class MongoImportBuffer
    include Logjam::Helpers

    def initialize(dbname, publisher)
      @db_date = Logjam.db_date(dbname)
      @old_buffer = @db_date && @db_date < Date.today
      database = Logjam.connection_for(dbname).db(dbname)
      Logjam.ensure_known_database(dbname)
      @totals  = Totals.ensure_indexes(database["totals"])
      @minutes = Minutes.ensure_indexes(database["minutes"])
      @quants  = Quants.ensure_indexes(database["quants"])

      @publisher = publisher
      @state = nil
    end

    def add_values(state)
      return 0 if state.blank?
      if @state
        @state[:modules].merge(state[:modules])
        state[:errors].each do |mod,errors|
          (@state[:errors][mod]||=[]).concat(errors)
        end
        [:totals, :minutes, :quants].each do |k|
          merge_values(@state[k], state[k])
        end
      else
        @state = state
      end
      state.delete(:count) || 0
    end

    def flush_and_publish
      publish_unless_old_buffer
      flush_totals_buffer(@state[:totals])
      flush_minutes_buffer(@state[:minutes])
      flush_quants_buffer(@state[:quants])
    ensure
      @state = nil
    end

    # dirty hack to avoid publishing request data from the previous day
    # this would better be handled in class MongoImporter
    def publish_unless_old_buffer
      if @old_buffer
        log_info "skipping publishing old data"
      else
        # log_info "publishing fresh data"
        @publisher.publish(@state[:modules], @state[:totals], @state[:errors])
      end
    end

    private

    def merge_values(a,b)
      b.each do |mod,b_values|
        a_values = (a[mod] ||= {})
        b_values.each do |k,v|
          a_values[k] = (a_values[k]||0) + v
        end
      end
    end

    UPSERT_ONE = {:upsert => true, :multi => false}

    def flush_quants_buffer(quants_buffer)
      quants = @quants
      quants_buffer.each do |(p,k,q),inc|
        quants.update({"page" => p, "kind" => k, "quant" => q}, {'$inc' => inc}, UPSERT_ONE)
      end
    end

    def flush_minutes_buffer(minutes_buffer)
      minutes = @minutes
      minutes_buffer.each do |(p,m),inc|
        minutes.update({"page" => p, "minute" => m}, {'$inc' => inc}, UPSERT_ONE)
      end
    end

    def flush_totals_buffer(totals_buffer)
      totals = @totals
      totals_buffer.each do |(p,inc)|
        totals.update({"page" => p}, {'$inc' => inc}, UPSERT_ONE)
      end
    end
  end
end

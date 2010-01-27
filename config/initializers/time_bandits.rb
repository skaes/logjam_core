TimeBandits.add TimeBandits::TimeConsumers::Memcached if defined?(Memcached)
TimeBandits.add TimeBandits::TimeConsumers::GarbageCollection.instance if GC.respond_to? :enable_stats

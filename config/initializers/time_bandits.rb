TimeBandits.add TimeBandits::TimeConsumers::Memcached
TimeBandits.add TimeBandits::TimeConsumers::GarbageCollection.instance if GC.respond_to? :enable_stats

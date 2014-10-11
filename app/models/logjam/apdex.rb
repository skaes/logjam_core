module Logjam

  module Apdex
    extend self

    FRONTEND_RESOURCE_TYPES = %i(frontend dom)

    def apdex(section = :backend)
      case section
      when :frontend, "frontend_time" then "fapdex"
      when :backend, "total_time"     then "apdex"
      when :ajax, "ajax_time"         then "xapdex"
      when :page, "page_time"         then "papdex"
      else
        if FRONTEND_RESOURCE_TYPES.include?(Logjam::Resource.resource_type(section))
          :papdex
        else
          :apdex
        end
      end
    end

    def counter(section = :backend)
      case section
      when :ajax, "ajax_time"         then "ajax_count"
      when :page, "page_time"         then "page_count"
      when :frontend, "frontend_time" then "frontend_count"
      when :backend, "total_time"     then "count"
      else
        if FRONTEND_RESOURCE_TYPES.include?(Logjam::Resource.resource_type(section))
          "page_count"
        else
          "count"
        end
      end
    end

  end
end

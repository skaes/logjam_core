module ResourcesHelper
  def descriptions
    resources = Resource.time_resources + Resource.memory_resources + Resource.call_resources
    groupings = Resource.groupings
    functions = Resource.grouping_functions.reject(&:blank?)
    g = {}
    groupings.each do |grouping|
      r = {}
      resources.each do |resource|
        if Resource.grouping?(grouping)
          f = {}
          functions.each do |function|
            f[function] = Resource.description(resource, grouping, function)
          end
          r[resource] = f
        else
          r[resource] = Resource.description(resource, grouping, nil) unless resource == 'requests'
        end
        g[grouping] = r
      end
    end
    g.to_json
  end
end

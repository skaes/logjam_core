module ResourcesHelper
  def descriptions
    resources = Resource.time_resources + Resource.memory_resources + Resource.call_resources
    groupings = Resource.groupings
    functions = Resource.grouping_functions.reject(&:blank?)
    g = {}
    groupings.each do |grouping|
      r = {}
      resources.each do |resource|
        if grouping.to_sym == :request || resource.to_sym == :requests
          r[resource] = Resource.description(resource, grouping, :sum)
        else
          f = {}
          functions.each do |function|
            f[function] = Resource.description(resource, grouping, function)
          end
          r[resource] = f
        end
        g[grouping] = r
      end
    end
    g.to_json
  end
end

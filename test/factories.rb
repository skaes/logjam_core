Factory.define :yesterday do |a|
  a.host 'server'
  a.process_id 0
  a.user_id 0
  a.page 'controller#action'
  a.minute1 0
  a.minute2 0
  a.minute5 0
  a.started_at Date.yesterday.beginning_of_day
  a.response_code 200

  a.session_id 'session' if ControllerAction.instance_methods.include? :session_id=
  a.new_session false if ControllerAction.instance_methods.include? :new_session=
  a.heap_growth 0 if ControllerAction.instance_methods.include? :heap_growth=

  Resource.time_resources.each do |resource|
    a.send(resource, 0.0)
  end
  (Resource.call_resources - ['1']).each do |resource|
    a.send(resource, 0)
  end
  Resource.memory_resources.each do |resource|
    a.send(resource, 0)
  end
end

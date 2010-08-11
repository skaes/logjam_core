ActionController::Routing::Routes.draw do |map|
  map.auto_complete "#{Logjam.base_url}/logjam/:action",
                    :controller => 'logjam/logjam',
                    :requirements => { :action => /auto_complete_for_\S+/ },
                    :conditions => { :method => :get }

  map.connect "#{Logjam.base_url}/:year/:month/:day/:action/:id", :controller => "logjam/logjam",
     :requirements => {:year => /\d\d\d\d/, :month => /\d\d/, :day => /\d\d/}

  map.connect "#{Logjam.base_url}/:controller/:action/:id"
end

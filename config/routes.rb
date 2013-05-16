Rails.application.routes.draw do

  controller "logjam/logjam" do
    scope "#{Logjam.base_url}" do

      get "/live_stream" => :live_stream

      get "/call_relationships" => :call_relationships

      get "/:year/:month/:day(/:action(/:id))", :year => /\d\d\d\d/, :month => /\d\d/, :day => /\d\d/

      get "/" => :index, :page => "::"

    end
  end
end

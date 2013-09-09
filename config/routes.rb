Rails.application.routes.draw do

  scope "#{Logjam.base_url}" do
    controller "logjam/logjam" do
      get "/live_stream" => :live_stream

      get "/call_relationships" => :call_relationships

      get "/call_graph" => :call_graph

      get "/database_information" => :database_information

      get "/:year/:month/:day(/:action(/:id))", :year => /\d\d\d\d/, :month => /\d\d/, :day => /\d\d/

      get "/" => :index, :page => "::"
    end

    controller "logjam/admin" do
      get "/admin/storage" => :index, :as => "admin_storage"
    end
  end
end

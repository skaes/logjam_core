Rails.application.routes.draw do

  controller "logjam/logjam" do

    get "/live_stream" => :live_stream, :format => false
    get "/call_relationships" => :call_relationships
    get "/call_graph" => :call_graph
    get "/database_information" => :database_information

    constraints(:year => /\d\d\d\d/, :month => /\d\d/, :day => /\d\d/) do
      get "/auto_complete_for_controller_action_page" => :auto_complete_for_controller_action_page
      get "/auto_complete_for_applications_page" => :auto_complete_for_applications_page

      get "/:year/:month/:day" => :index
      get "/:year/:month/:day/allocated_objects_distribution" => :allocated_objects_distribution
      get "/:year/:month/:day/allocated_size_distribution" => :allocated_size_distribution
      get "/:year/:month/:day/apdex_overview" => :apdex_overview
      get "/:year/:month/:day/call_graph" => :call_graph
      get "/:year/:month/:day/call_relationships" => :call_relationships
      get "/:year/:month/:day/callers" => :callers
      get "/:year/:month/:day/database_information" => :database_information
      get "/:year/:month/:day/enlarged_plot" => :enlarged_plot
      get "/:year/:month/:day/error_overview" => :error_overview
      get "/:year/:month/:day/errors" => :errors
      get "/:year/:month/:day/exceptions" => :exceptions
      get "/:year/:month/:day/history" => :history
      get "/:year/:month/:day/js_exception_types" => :js_exception_types
      get "/:year/:month/:day/js_exceptions" => :js_exceptions
      get "/:year/:month/:day/leaders" => :leaders
      get "/:year/:month/:day/live_stream" => :live_stream
      get "/:year/:month/:day/request_overview" => :request_overview
      get "/:year/:month/:day/request_time_distribution" => :request_time_distribution
      get "/:year/:month/:day/response_code_overview" => :response_code_overview
      get "/:year/:month/:day/response_codes" => :response_codes
      get "/:year/:month/:day/show/:id" => :show
      get "/:year/:month/:day/totals_overview" => :totals_overview
      get "/:year/:month/:day/user_agents" => :user_agents
    end

    get "/" => :index, :page => "::"
  end

  controller "logjam/admin" do
    get "/admin/storage" => :index, :as => "admin_storage"
    get "/admin/streams" => :streams
  end
end

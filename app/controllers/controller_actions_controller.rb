class ControllerActionsController < ApplicationController
  # GET /controller_actions
  # GET /controller_actions.xml
  before_filter :redirect_to_clean_url
  if RAILS_ENV=="development"
    before_filter :print_params
  end

  def auto_complete_for_controller_action_page
    prepare_params
    re = /#{params[:controller_action][:page]}/i
    pages = Totals.new(@date).page_names.select {|name| name =~ re}
    modules = pages.map{|p| p =~ /^(.+?)::/ && $1 }.compact.uniq
    @completions = (pages + modules).sort
    render :inline => "<%= content_tag(:ul, @completions.map { |page| content_tag(:li, page) }) %>"
  end

  def index
    @dataset = dataset_from_params
    @plot = Plot.new(@dataset, :png)

    respond_to do |format|
      format.html { render :template => "/controller_actions/index.html.erb" }
      format.xml  { render :xml => @controller_actions }
    end
  end

  def show
    get_date
    @request = Requests.new(@date).find(params[:id])
  end

  def errors
    get_date
    determine_page_pattern
    q = Requests.new(@date, "minute", @page, :response_code => 500, :limit => 500)
    @error_count = q.count
    @requests = q.all
  end

  def enlarged_plot
    @dataset = dataset_from_params
    @plot = Plot.new(@dataset, :svg)
  end

  def request_time_distribution
    @dataset = dataset_from_params
    @dataset.plot_kind = :request_time_distribution
    @plot = Plot.new(@dataset, :svg)
  end

  def allocated_objects_distribution
    @dataset = dataset_from_params
    @dataset.plot_kind = :allocated_objects_distribution
    @plot = Plot.new(@dataset, :svg)
  end

  def allocated_size_distribution
    @dataset = dataset_from_params
    @dataset.plot_kind = :allocated_size_distribution
    @plot = Plot.new(@dataset, :svg)
  end

  private

  def default_date
    (Logjam.database_days.first || Date.today).to_date
  end

  def get_date
    @date = "#{params['year']}-#{params['month']}-#{params['day']}".to_date unless params[:year].blank?
    @date ||= default_date
  end

  def prepare_params
    get_date
    params[:end_hour] ||= FilteredDataset::DEFAULTS[:end_hour]
    params[:resource] ||= FilteredDataset::DEFAULTS[:resource]
    params[:grouping] ||= FilteredDataset::DEFAULTS[:grouping]
    params[:grouping_function] ||= FilteredDataset::DEFAULTS[:grouping_function]
    if params[:resource] == 'requests'
      params[:grouping] = 'page' if params[:grouping] == 'request'
      params[:grouping_function] = 'sum'
    end
    @plot_kind = Resource.resource_type(params[:resource])
    @attributes = Resource.resources_for_type(@plot_kind) - ['requests']
    determine_page_pattern
  end

  def dataset_from_params
    prepare_params
    params[:controller_action] = {:page => @page}
    params[:interval] ||= FilteredDataset::DEFAULTS[:interval]

    FilteredDataset.new(:date => @date,
                        :interval => params[:interval].to_i,
                        :user_id => params[:user_id],
                        :host => params[:server],
                        :page => @page_pattern,
                        :response_code => params[:response],
                        :heap_growth_only => params[:heap_growth_only],
                        :plot_kind => @plot_kind,
                        :resource => params[:resource] || :total_time,
                        :grouping => params[:grouping],
                        :grouping_function => (params[:grouping_function] || :avg).to_sym,
                        :start_hour => params[:start_hour].to_i,
                        :end_hour => params[:end_hour].to_i)
  end

  def redirect_to_clean_url
    if params[:starts_at] =~ /^(\d\d\d\d)-(\d\d)-(\d\d)$/
      redirect_to({:controller => controller_name, :action => params[:action], :year => $1, :month => $2, :day => $3,
                    :start_hour => params[:start_hour], :end_hour => params[:end_hour],
                    :server => params[:server], :controller_action => params[:controller_action], :response => params[:response],
                    :heap_growth_only => params[:heap_growth_only], :resource => params[:resource], :grouping => params[:grouping],
                    :grouping_function => params[:grouping_function], :interval => params[:interval],
                    :user_id => params[:user_id]}.reject{|k,v| v.blank? || FilteredDataset.is_default?(k, v) || (k == :controller_action && v == {'page' => ''})})
    end
  end

  def print_params
    p params
  end

  def determine_page_pattern
    @page = params[:controller_action] ? params[:controller_action][:page] : params[:page]
    @page_pattern = @page
    return if @page_pattern.blank?
    @page_pattern.gsub!(/[*%]/,'')
    page_names = Totals.new(@date).page_names
    if !page_names.select{|p| p =~ /^#{@page_pattern}$/}.first
      if !page_names.select{|p| p =~ /^#{@page_pattern}/}.first
        @page_pattern = "%#{@page_pattern}%"
      else
        @page_pattern = "#{@page_pattern}%"
      end
    end
  end
end

import URI from "urijs";
import $ from "jquery";
import context from "./page-context.js";

export function submit_filter_form() {
  var selected_date = $("#datepicker").val().replace(/-/g,'/');
  if (selected_date.match(/\d\d\d\d\/\d\d\/\d\d/)) {
    var old_action = $("#filter-form").attr("action");
    var old_date = old_action.match(/\d\d\d\d\/\d\d\/\d\d/);
    if (old_date) {
      $("#filter-form").attr("action", old_action.replace(old_date[0], selected_date));
    }
  }
  let defaults = context.parameter_defaults;
  var action = new URI ($("#filter-form").attr("action"));
  var x = $("#filter-form").serialize();
  var uri = new URI();
  uri.pathname(action.pathname().replace(/\/show\/.*$/, ''));
  uri.search(x);
  uri.removeSearch("utf8")
     .removeSearch("page", defaults.page)
     .removeSearch("resource", defaults.resource)
     .removeSearch("section", defaults.section)
     .removeSearch("scale", defaults.scale)
     .removeSearch("time_range", defaults.time_range)
     .removeSearch("grouping", defaults.grouping)
     .removeSearch("grouping_function", defaults.grouping_function)
     .removeSearch("error_type", defaults.error_type)
     .removeSearch("start_minute", defaults.start_minute)
     .removeSearch("end_minute", defaults.end_minute)
     .removeSearch("auto_refresh", defaults.auto_refresh)
     .removeSearch("kind", defaults.kind)
     .removeSearch("interval", defaults.interval);
  document.location.href = uri.toString();
}

window.submit_filter_form = submit_filter_form;

function go_home() {
  let defaults = context.parameter_defaults;
  let home_url = context.home_url;
  $("#page").val(defaults.page);
  $("#grouping").val(defaults.grouping);
  $("#resource").val(defaults.resource);
  $("#section").val(defaults.section);
  $("#scale").val(defaults.scale);
  $("#kind").val(defaults.kind);
  $("#grouping-function").val(defaults.grouping_function);
  $("#error-type").val(defaults.error_type);
  $("#start-minute").val(defaults.start_minute);
  $("#end-minute").val(defaults.end_minute);
  $("#interval").val(defaults.interval);
  $("#time-range").val(defaults.time_range);
  $("#auto_refresh").val(defaults.auto_refresh);
  $("#filter-form").attr("action", home_url);
  $("#filter-form").trigger("submit");
}

window.go_home = go_home;

function view_selected_pages(){

  if (context.parameters.time_range == "date") {
    $("#filter-form").attr("action", context.self_url);
  }
  else {
    $("#filter-form").attr("action", context.history_url);
  }
  $("#filter-form").trigger("submit");
}

window.view_selected_pages = view_selected_pages;

function view_grouping(grouping){
  let defaults = context.parameter_defaults;
  let home_url = context.home_url;
  $("#grouping").val(grouping);
  $("#time-range").val(defaults.time_range);
  $("#filter-form").attr("action", home_url);
  $("#filter-form").trigger("submit");
}

window.view_grouping = view_grouping;

function view_resource(resource){
  let parameters = context.parameters;
  let defaults = context.parameter_defaults;
  let home_url = context.home_url;
  $("#resource").val(resource);
  $("#time-range").val(defaults.time_range);
  if (parameters.action != "totals_overview") {
    $("#filter-form").attr("action", home_url);
  }
  if (parameters.grouping_function == "apdex" && !(resource.match(/time/) || resource == "dom_interactive")) {
    $("#grouping-function").val(defaults.grouping_function);
  }

  let frontendResources = ['page_time', 'navigation_time', 'connect_time', 'request_time', 'response_time', 'processing_time', 'load_time', 'dom_interactive', 'ajax_time', 'style_nodes', 'script_nodes', 'html_nodes'];
  if (frontendResources.indexOf(resource) > -1) {
    $('#section').val('frontend');
  } else {
    $('#section').val('backend');
  }

  $("#filter-form").trigger("submit");
}

window.view_resource = view_resource;

function view_time_range(time_range){
  let history_url = context.history_url;
  $("#time-range").val(time_range);
  if (time_range == "date") {
    $("#filter-form").attr("action", document.home_url);
  } else {
    $("#filter-form").attr("action", history_url);
  }
  $("#filter-form").trigger("submit");
}

window.view_time_range = view_time_range;

export function view_date(date) {
  let home_url = context.home_url;
  $("#datepicker").val(date.toJSON().substr(0,10));
  $("#time-range").val("date");
  $("#filter-form").attr("action", home_url);
  submit_filter_form();
}

function sort_by(order){
  $('#grouping-function').val(order);
  $("#filter-form").trigger("submit");
}

window.sort_by = sort_by;

function initialize_header() {
  $("#filter-form").on("submit", function(event) {
    event.preventDefault();
    submit_filter_form();
  });

  let parameters = context.parameters;
  let selectable_days = context.selectable_days;
  if (parameters.time_range == "date") {
    $("#datepicker").jdPicker({
      date_format: "YYYY-mm-dd",
      selectable: selectable_days,
      error_out_of_range: "No data for that date."
    });
  }

/*  $("#namespace-suggest").autocomplete({
    serviceUrl: action_auto_complete_url,
    minChars: 0,
    maxHeight: 300,
    width: 250,
    zIndex:100000,
    onSelect: function(value){
      $('#page').val( value.value );
      submit_filter_form();
    }
  });*/

  let action_auto_complete_url = context.action_auto_complete_url;
  $("#namespace-suggest").select2({
    width: 300,
    minimumInputLength: 0,
    ajax: {
      url: action_auto_complete_url,
      dataType: 'json',
      data: function (term, page) {
        return { query: term };
      },
      results: function (data, page) {
        var array = [];
        /* add the current term to the list */
        if (data.query.length > 0) {
          array.push({id: 0, text: data.query});
        }

        data.suggestions.forEach(function(item, index){
          array.push({id: index+1, text: item});
        });
        return {results: array};
      }
    }
  });

  $("#namespace-suggest").on("change", function(value){
    $('#page').val( value.added.text );
    submit_filter_form();
  });

  $("#namespace-suggest").on("blur", function(value){
    $("#namespace-suggest").select2('close');
    submit_filter_form();
  });

  $("#application-suggest").select2({
    width: 150,
    minimumInputLength: 0
  });

  $("#application-suggest").on("change", function(value){
      $('#app').val( value.added.text );
      submit_filter_form();
  });

  $("#application-suggest").on("blur", function(value){
    // console.log('blur');
    $("#application-suggest").select2('close');
    submit_filter_form();
  });

  $("#view-backend").on("click", function(){
    $("#section").val("backend");
    submit_filter_form();
  });

  $("#view-frontend").on("click", function(){
    $("#section").val("frontend");
    submit_filter_form();
  });

  $("#view-linear-scale").on("click", function(){
    $("#scale").val("linear");
    submit_filter_form();
  });

  $("#view-log-scale").on("click", function(){
    $("#scale").val("logarithmic");
    submit_filter_form();
  });

  $("#view-apdex-total-time").on("click", function(){
    $("#section").val("backend");
    $("#resource").val("total_time");
    submit_filter_form();
  });

  $("#view-apdex-page-time").on("click", function(){
    $("#resource").val("page_time");
    $("#section").val("frontend");
    submit_filter_form();
  });

  $("#view-apdex-ajax-time").on("click", function(){
    $("#resource").val("ajax_time");
    $("#section").val("frontend");
    submit_filter_form();
  });


/*  $("#application-suggest").autocomplete({
    serviceUrl: application_auto_complete_url,
    minChars: 0,
    maxHeight: 300,
    width: 150,
    zIndex:100000,

    tabDisabled: true,
    onSelect: function(value){
      $('#app').val( value.value );
      $('#page').val( '' );
      submit_filter_form();
    }
  });*/
}

window.initialize_header = initialize_header;

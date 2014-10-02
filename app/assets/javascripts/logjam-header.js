function submit_filter_form() {
  var selected_date = $("#datepicker").val().replace(/-/g,'/');
  if (selected_date.match(/\d\d\d\d\/\d\d\/\d\d/)) {
    var old_action = $("#filter-form").attr("action");
    var old_date = old_action.match(/\d\d\d\d\/\d\d\/\d\d/);
    if (old_date) {
      $("#filter-form").attr("action", old_action.replace(old_date[0], selected_date));
    }
  }
  var action = new URI ($("#filter-form").attr("action"));
  var x = $("#filter-form").serialize();
  var uri = new URI();
  uri.pathname(action.pathname());
  uri.search(x);
  uri.removeSearch("utf8")
     .removeSearch("page", parameter_defaults.page)
     .removeSearch("resource", parameter_defaults.resource)
     .removeSearch("time_range", parameter_defaults.time_range)
     .removeSearch("grouping", parameter_defaults.grouping)
     .removeSearch("grouping_function", parameter_defaults.grouping_function)
     .removeSearch("start_minute", parameter_defaults.start_minute)
     .removeSearch("end_minute", parameter_defaults.end_minute)
     .removeSearch("interval", parameter_defaults.interval);
  document.location.href = uri.toString();
}

function go_home() {
  $("#page-field").val(parameter_defaults.page);
  $("#grouping").val(parameter_defaults.grouping);
  $("#resource").val(parameter_defaults.resource);
  $("#grouping-function").val(parameter_defaults.grouping_function);
  $("#start-minute").val(parameter_defaults.start_minute);
  $("#end-minute").val(parameter_defaults.end_minute);
  $("#interval").val(parameter_defaults.interval);
  $("#time-range").val(parameter_defaults.time_range);
  $("#filter-form").attr("action", home_url);
  $("#filter-form").submit();
}

function view_selected_pages(){

  if (parameters.time_range == "date") {
    $("#filter-form").attr("action", self_url);
  }
  else {
    $("#filter-form").attr("action", history_url);
  }
  $("#filter-form").submit();
}

function view_grouping(grouping){
  $("#grouping").val(grouping);
  $("#time-range").val(parameter_defaults.time_range);
  $("#filter-form").attr("action", home_url);
  $("#filter-form").submit();
}

function view_resource(resource){
  $("#resource").val(resource);
  $("#time-range").val(parameter_defaults.time_range);
  if (parameters.action != "totals_overview") {
    $("#filter-form").attr("action", home_url);
  }
  if (parameters.grouping_function == "apdex" && !(resource.match(/time/))) {
    $("#grouping-function").val(parameter_defaults.grouping_function);
  }
  $("#filter-form").submit();
}

function view_time_range(time_range){
  $("#time-range").val(time_range);
  if (time_range == "date") {
    $("#filter-form").attr("action", home_url);
  } else {
    $("#filter-form").attr("action", history_url);
  }
  $("#filter-form").submit();
}

function view_date(date) {
  $("#datepicker").val(date.toJSON().substr(0,10));
  $("#time-range").val("date");
  $("#filter-form").attr("action", home_url);
  submit_filter_form();
}

function sort_by(order){
  $('#grouping-function').val(order);
  $('#filter-form').submit();
}

function initialize_header() {
  $("#filter-form").on("submit", function(event) {
    event.preventDefault();
    submit_filter_form();
  });

  if (parameters.time_range == "date") {
    $("#datepicker").jdPicker({
      date_format: "YYYY-mm-dd",
      selectable: selectable_days,
      error_out_of_range: "No data for that date."
    });
  }

  $("#namespace-suggest").autocomplete({
    serviceUrl: action_auto_complete_url,
    minChars: 0,
    maxHeight: 300,
    width: 250,
    zIndex:100000,
    autoSelectFirst: true,
    onSelect: function(value){
      $('#page').val( value.value );
      submit_filter_form();
    }
   });

  $("#application-suggest").autocomplete({
    serviceUrl: application_auto_complete_url,
    minChars: 0,
    maxHeight: 300,
    width: 150,
    zIndex:100000,
    autoSelectFirst: true,
    onSelect: function(value){
      $('#app').val( value.value );
      $('#page').val( '' );
      submit_filter_form();
    }
   });
}

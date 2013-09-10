function submit_filter_form() {
  var selected_date = $("#datepicker").val().replace(/-/g,'/');
  if (selected_date.match(/\d\d\d\d\/\d\d\/\d\d/)) {
    var action = $("#filter-form").attr("action");
    var old_date = action.match(/\d\d\d\d\/\d\d\/\d\d/);
    if (old_date) {
      $("#filter-form").attr("action", action.replace(old_date[0], selected_date));
    }
  }
  var action = new URI ($("#filter-form").attr("action"));
  var x = $("#filter-form").serialize();
  var uri = new URI();
  uri.pathname(action.pathname());
  uri.search(x);
  uri.removeSearch("utf8")
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
  $("#page-field").val("::");
  $("#grouping option:selected").val(parameter_defaults.grouping);
  $("#resource option:selected").val(parameter_defaults.resource);
  $("#grouping_function").val(parameter_defaults.grouping_function);
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
  $("#grouping option:selected").val(grouping);
  $("#time-range").val(parameter_defaults.time_range);
  $("#filter-form").attr("action", home_url);
  $("#filter-form").submit();
}

function view_resource(resource){
  $("#resource option:selected").val(resource);
  $("#time-range").val(parameter_defaults.time_range);
  if (parameters.action != "totals_overview") {
    $("#filter-form").attr("action", home_url);
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
  $('#grouping_function option:selected').val(order);
  $('#filter-form').submit();
}

function submit_minutes(start, end, resource) {
   $('#start-minute').val(""+start);
   $('#end-minute').val(""+end);
   $('#grouping option:selected').val("request");
   submit_resource(resource);
}

function submit_resource(resource) {
   if (d3.event) {
     d3.event.preventDefault();
     d3.event.stopPropagation();
   }
   if (resource != "requests/second" && resource != "free slots") {
     $('#resource option:selected').val(resource.replace(/ /g,'_'));
     $('#filter-form').attr("action", home_url);
     submit_filter_form();
   }
}

function restrict_minutes(p, resource){
   start = Math.max(0, Math.floor(x.invert(p[0]))*interval-interval);
   end = start+interval;
   submit_minutes(start, end, resource);
}

function reset_minutes(){
   submit_minutes(0, 1440, $('#resource option:selected').val());
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
          error_out_of_range: "No data for that date."});
  }

  $("#page-field").autocomplete({
     serviceUrl: auto_complete_url,
     minChars: 1,
     maxHeight: 600,
     onSelect: function(value, data){ submit_filter_form(); }
   });

  $("*[title]").tipsy({gravity:"nw", opacity:0.9, offset:10, delayIn:250, delayOut:0, fade:false});

  // bug in safari leaves the tooltips open and you can have more than one shown
  if ($.browser.safari) {
    $(window).on("beforeunload", function(e){ $(".tipsy").remove(); });
  }
}

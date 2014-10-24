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
     .removeSearch("section", parameter_defaults.section)
     .removeSearch("time_range", parameter_defaults.time_range)
     .removeSearch("grouping", parameter_defaults.grouping)
     .removeSearch("grouping_function", parameter_defaults.grouping_function)
     .removeSearch("start_minute", parameter_defaults.start_minute)
     .removeSearch("end_minute", parameter_defaults.end_minute)
     .removeSearch("auto_refresh", parameter_defaults.auto_refresh)
     .removeSearch("interval", parameter_defaults.interval);
  document.location.href = uri.toString();
}

function go_home() {
  $("#page-field").val(parameter_defaults.page);
  $("#grouping").val(parameter_defaults.grouping);
  $("#resource").val(parameter_defaults.resource);
  $("#section").val(parameter_defaults.section);
  $("#grouping-function").val(parameter_defaults.grouping_function);
  $("#start-minute").val(parameter_defaults.start_minute);
  $("#end-minute").val(parameter_defaults.end_minute);
  $("#interval").val(parameter_defaults.interval);
  $("#time-range").val(parameter_defaults.time_range);
  $("#auto_refresh").val(parameter_defaults.auto_refresh);
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

  frontendResources = ['page_time', 'connect_time', 'request_time', 'response_time', 'processing_time', 'load_time', 'ajax_time', 'style_nodes', 'script_nodes', 'html_nodes'];
  if(frontendResources.indexOf(resource) > -1) {
    $('#section').val('frontend');
  } else {
    $('#section').val('backend');
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

  $("#namespace-suggest").select2({
    width: 350,
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
        if(data.query.length > 0) { array.push({id: 0, text: data.query}) }

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
      $('#page').val( '' );
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

function logjam_live_stream_chart(params){
  var resources = params.resources;
  var colors = params.colors;
  var connection_status = "disconnected";
  var legend = params.legend;
  var warning_level = 3;
  var update_interval = 1;
  var transparent_ico_path = params.transparent_ico_path;

  /* Sizing and scales. */
  var w = parseInt(document.getElementById('live-stream-chart').offsetWidth - 100, 10),
      h = 300,
      slice = 10,
      x = d3.scale.linear().domain([0, 600]).range([0, w]),
      y = d3.scale.linear().domain([0, 100]).range([h, 0]).nice(),
      y2 = d3.scale.linear([0, 0]).range([50,0]).nice(),
      color_map = d3.scale.ordinal().domain(colors);
  var c = color_map.range();

  /* Data */
  function zeros(){ return d3.range(600/slice+2).map(function(){ return 0;}); }
  var data = d3.range(resources.length).map(zeros);
  var request_counts = zeros();

  var vis = d3.select("#live-stream-chart")
        .append("svg")
        .attr("width", w+70)
        .attr("height", h+70)
        .style("stroke", "#999")
        .style("strokeWidth", 1.0)
        .append("g")
        .attr("transform", "translate(40,10)");

  function connection_status_color() {
    switch(connection_status) {
    case 'connected'   : return "rgba(123,128,128,.5)";
    case 'connecting'  : return "rgba(0,128,128,.5)";
    case 'disconnected': return "rgba(123,0,0,.5)";
    default            : return "black";
    }
  }

  /* Connection status. */
  var status_label = vis.append("text")
        .attr("x", 4)
        .attr("y", 4)
        .attr("text-anchor", "start")
        .attr("dy", ".71em")
        .style("font", "bold 14px open sans")
        .style("fill", connection_status_color)
        .style("stroke", "none")
        .text(connection_status);

  /* Vertical grid lines */
  vis.selectAll(".yrule")
    .data(x.ticks(w/slice))
    .enter()
    .append("line")
    .attr("class", "yrule")
    .style("stroke", function(d, i){ return (i%60)==0 ?"#999" : "rgba(128,128,128,.2)"; })
    .attr("x1", x)
    .attr("y1", 0)
    .attr("x2", x)
    .attr("y2", h);

  /* X-axis labels */
  vis.selectAll(".x-axis-label")
    .data(x.ticks(6))
    .enter()
    .append("text")
    .attr("x", x)
    .attr("y", h+5)
    .attr("dx", 2)
    .attr("text-anchor", "middle")
    .attr("dy", ".71em")
    .style("font", "10px open sans")
    .style("fill", "#000")
    .style("stroke", "none")
    .attr("display", function(d){ return (d && ((d/slice)%10==0)) ? null : "none";})
    .text(function(d){ return "t"+ (d/slice-60);});

  /* top x axis */
  vis.append("line")
    .attr("y1", 0)
    .attr("x1", 0)
    .attr("y2", 0)
    .attr("x2", w)
    .style("stroke", "#999")
    .style("fill", "none");

  /* Y-label */
  vis.append("svg:text")
    .attr("class", "label")
    .attr("dy", -25)
    .attr("dx", -w/2+140)
    .style("font", "14px open sans")
    .style("fill", "#999")
    .style("stroke", "none")
    .attr("text-anchor", "middle")
    .attr("transform", "rotate(270)")
    .text("Response time (ms)");

  var area = d3.svg.area()
        .interpolate("cardinal")
        .x(function(d) { return x(d.x*slice); })
        .y0(function(d) { return y(d.y0); })
        .y1(function(d) { return y(d.y + d.y0); });

  function oj(a) {
    return a.map(function(d){
      return d.map(function(d,i ){ return {x:i, y:d, y0:0}; });
    });
  };

  var odata = oj(data);
  var ldata = d3.layout.stack()(odata);

  vis.append("svg:clipPath")
    .attr("id", "clip")
    .append("svg:rect")
    .attr("width", w)
    .attr("height", h);

  var clip = vis.append("g").attr("clip-path", "url(#clip)");

  var pane = clip.append("g");

  /* The stack layout. */
  pane.selectAll(".layer")
    .data(ldata)
    .enter().append("path")
    .attr("class", "layer")
    .style("fill", function(d,i) { return colors[i]; })
    .style("stroke", function(d,i) { return colors[i]; })
    .attr("d", area);


  /* Request counts. */
  var request_area = d3.svg.area()
        .interpolate("cardinal")
        .x(function(d) { return x(d.x*slice); })
        .y0(function(d) { return y2(d.y0); })
        .y1(function(d) { return y2(d.y + d.y0); });

  var request_data = request_counts.map(function(d,i){ return {x:i, y:d, y0:0};});
  pane.selectAll(".request_count")
    .data([request_data])
    .enter().append("path")
    .attr("class", "request_count")
    .style("fill", "rgba(128,128,128,0.3)")
    .style("stroke", "rgba(64,64,64,0.3)")
    .attr("d", request_area);

  /* Legend. */
  vis.selectAll(".legend")
    .data(legend)
    .enter().append("svg:text")
    .attr("class", "legend")
    .attr("x", function(d,i){ return 10+(120*(Math.floor(i/2))); })
    .attr("y", function(d,i){ return h+30+14*(i%2); })
    .style("font", "10px open sans")
    .style("stroke", "none")
    .style("fill", "#000")
    .text(String);

  vis.selectAll(".legendmark")
    .data(legend)
    .enter().append("svg:circle")
    .attr("class", "legendmark")
    .attr("transform", "translate(-7,-3)")
    .attr("cx", function(d,i){ return 10+(120*(Math.floor(i/2))); })
    .attr("cy", function(d,i){ return h+30+14*(i%2); })
    .attr("r", 4)
    .style("stroke", function(d,i){ return colors[i]; })
    .style("fill", function(d,i){ return colors[i]; });

  var request_count_formatter = d3.format(",.0f");

  vis.selectAll(".rlabel")
    .data([50,25,0])
    .enter()
    .append("text")
    .style("stroke", "none")
    .style("fill", "#000")
    .attr("class", "rlabel")
    .style("font", "10px open sans")
    .attr("text-anchor", "end")
    .attr("y", function(d,i){ return 50-i*25-1; })
    .attr("x", w-1)
    .text(function(d){ return request_count_formatter(y2.invert(d)); });

  /* recompute the Y-scale. */
  function re_scale() {
    var max_y = 0;
    var num_areas = data.length;
    var num_slots = data[0].length;
    for (var i = 0; i < num_slots; ++i) {
      var sum_slot = 0;
      for (var j = 0; j < num_areas; ++j) sum_slot += data[j][i];
      if (sum_slot > max_y) max_y = sum_slot;
    };
    y = d3.scale.linear().domain([0, max_y]).range([h,0]).nice();
    y2 = d3.scale.linear().domain([0, d3.max(request_counts)]).range([50,0]).nice();
  };

  /* add stream data to the chart */
  function update_chart(values) {
    var count = values["count"];
    request_counts.push(count);
    request_counts.shift();
    for (var i = 0, len = resources.length; i < len; ++i) {
      var val = values[resources[i]];
      if (count == 0 || val == null)
        val = 0;
      else
        val /= count;
      data[i].push(val);
      data[i].shift();
    };
    re_scale();
    redraw();
  };

  /* severity labels */
  function severity_label(i) {
    switch(i) {
    case 0: return "debug";
    case 1: return "info";
    case 2: return "warn";
    case 3: return "error";
    case 4: return "fatal";
    default: return "unknown";
    }
  };

  function severity_image(i) {
    var label = severity_label(i);
    return "<img src ='" + transparent_ico_path  + "' class='bg" + label + "' /> " + label.toUpperCase();
  }

  function error_url(request_id, time) {
    var date = time.slice(0,10).replace(/-/g,'/');
    return ('/' + date + '/show/' + request_id + '?' + params.app_env);
  };

  /* add errors to the recent errors list */
  function update_errors(errors) {
    var table = $('#recent-errors');
    var list = $('#recent-errors-head');
    for (var i = 0, len = errors.length; i < len; ++i) {
      var e = errors[i];
      var severity_value = e["severity"];
      if (severity_value < warning_level) {
        continue;
      }
      var severity = severity_image(severity_value);
      var response_code = e["response_code"];
      var action = e["action"];
      var time = e["time"].slice(11,19);
      var desc = e["description"].substring(0,80);
      var url = error_url(e["request_id"], e["time"]);
      var new_row = $("<tr class='full_stats'><td>" + severity + "</td><td>" + response_code + "</td><td>" + time + "</td><td>" + action + "</td><td>" + desc + "</td></tr>");
      new_row.hide().addClass("new_error clickable");
      var onclick = (function(u){ return function(){ window.open(u, "_blank");};})(url);
      new_row.children().click(onclick);
      var rows = $('#recent-errors tr');
      var l = rows.size() - 20;
      for (var j=0; j < l; ++j) {
        rows.last().remove();
      }
      new_row.removeAttr("style"); /* firefox bug */
      list.after(new_row);
      var remove_color = function(row) { return function() {
        window.setTimeout(function() { row.removeClass("new_error"); } , 10000); }; };
      new_row.fadeIn(2000, remove_color(new_row) );
    }
  };

  function update_anomaly_score(value) {
    var score = value["score"];
    var is_anomaly = value["anomaly"];
    $('#anomaly-score-value').html(d3.format(".2f")(score));
    $('#anomaly-score-value').css("color", is_anomaly ? "red" : "green");
    $('#anomaly-score').show();
  };

  /* update chart or error list */
  function update_view(value) {
    if ($.isArray(value))
      update_errors(value);
    else if ("anomaly" in value)
      update_anomaly_score(value);
    else
      update_chart(value);
  };

  /* The web socket */
  var ws = null;

  function redraw() {
    // Update
    odata = oj(data);
    ldata = d3.layout.stack()(odata);

    request_data = request_counts.map(function(d,i){ return {x:i, y:d, y0:0};});

    pane.selectAll(".layer")
      .data(ldata)
      .attr("d", area);

    pane.selectAll(".request_count")
      .data([request_data])
      .attr("d", request_area);

    pane
      .attr("transform", "translate(" + x(0) + ")")
      .transition()
      .ease("linear")
      .duration(update_interval)
      .attr("transform", "translate(" + x(-slice) + ")");

    vis.selectAll(".rlabel").data([50,25,0])
      .transition()
      .duration(100)
      .text(function(d){ return request_count_formatter(y2.invert(d)); });

    /* Horizontal grid lines */
    var vgrid = vis.selectAll(".xrule").data(y.ticks(10));

    vgrid.enter()
      .append("line")
      .attr("class", "xrule")
      .style("stroke", function(d,i){ return d ? "rgba(128,128,128,.2)" : "#999";})
      .attr("y1", y)
      .attr("x1", 0)
      .attr("y2", y)
      .attr("x2", w);

    vgrid.exit().remove();

    vgrid.transition()
      .duration(100)
      .attr("y1", y)
      .attr("y2", y);

    var vlabels = vis.selectAll(".ylabel").data(y.ticks(10));

    vlabels.enter().append("text")
      .attr("class", "ylabel")
      .attr("x", 0)
      .attr("y", y)
      .attr("dx", -10)
      .attr("dy", 3)
      .attr("text-anchor", "middle")
      .style("font", "10px open sans")
      .style("stroke", "none")
      .style("fill", "#000")
      .text(String);

    vlabels.exit().remove();

    vlabels.transition()
      .duration(100)
      .attr("y", y)
      .text(String);
  }

  function change_connection_status(new_status) {
    if (new_status != connection_status) {
      connection_status = new_status;
      status_label.transition().text(new_status).style("fill", connection_status_color);
    }
  }

  function reconnect(){
    var button = $('#stream-toggle');
    if ( button.val() == "pause") {
      change_connection_status("connecting");
      window.setTimeout(connect_chart, 5000);
    }
  };

  /* connect to the data stream */
  function connect_chart() {
    if ( ws == null ) {
      var Socket = "MozWebSocket" in window ? MozWebSocket : WebSocket;
      ws = new Socket(params.socket_url);
      ws.onmessage = function(evt) { update_view(JSON.parse(evt.data)); };
      ws.onclose = function() { change_connection_status("disconnected"); ws = null; reconnect(); };
      ws.onopen = function() { change_connection_status("connected"); ws.send(params.socket_greeting); };
      ws.onerror = function() { alert("websocket error"); };
    }
  };

  /* disconnect from the data stream */
  function disconnect_chart() {
    ws.close();
    ws = null;
  }

  /* toggle stream conection */
  function toggle_stream(button) {
    button.toggleClass('active');
    if (button.val() == "resume") {
      button.val("pause");
      connect_chart();
    } else {
      button.val("resume");
      disconnect_chart();
    }
  }

  /* toggle warning level */
  function toggle_warnings(button) {
    button.toggleClass('active');
    if (button.val() == "show warnings") {
      button.val("hide warnings");
      warning_level = 2;
    } else {
      button.val("show warnings");
      warning_level = 3;
    }
  }

  /* toggle smoothness */
  function toggle_smoothness(button) {
    button.toggleClass('active');
    if (button.val() == "smooth updates") {
      button.val("discrete updates");
      update_interval = 1000;
    } else {
      button.val("smooth updates");
      update_interval = 1;
    }
  }

  /* automatically connect to the data stream when the ducoment is ready */
  $(function(){
    $("#stream-toggle").on("click", function(){ toggle_stream($(this)); });
    $("#warnin-toggle").on("click", function(){ toggle_warnings($(this)); });
    $("#smooth-toggle").on("click", function(){ toggle_smoothness($(this)) ;});
    connect_chart();
  });
}

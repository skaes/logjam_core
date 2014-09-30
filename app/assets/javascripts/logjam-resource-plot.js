function logjam_resource_plot(params) {

  var events   = params.events;
  var data     = params.data;
  var interval = params.interval;
  var colors   = params.colors;
  var legend   = params.legend;
  var request_counts = params.request_counts;
  var gc_time = params.gc_time;
  var max_y = params.max_y;
  var zoomed_max_y = params.zoomed_max_y;
  var selected_slice = params.selected_slice;
  var selected_slice_width = params.selected_slice_width;
  var max_request_count = d3.max(request_counts);

  /* Animation */
  var zoom_interval = 1;

  /* Sizing and scales. */
  var w = document.getElementById('resource-plot').offsetWidth -70,
      h = params.h,
      xticks = d3.range(25).map(function(h){ return h/interval*60; }),
      x      = d3.scale.linear().domain([0, 1440/interval]).range([0, w]),
      y      = d3.scale.linear().domain([0, zoomed_max_y]).range([h, 0]).nice(),
      y2     = d3.scale.linear().domain([0, max_request_count]).range([50,0]).nice();

  function submit_minutes(start, end, resource) {
    $('#start-minute').val(""+start);
    $('#end-minute').val(""+end);
    $('#grouping').val("request");
    submit_resource(resource);
  }

  function submit_resource(resource) {
    if (d3.event) {
      d3.event.preventDefault();
      d3.event.stopPropagation();
    }
    if (resource != "requests/second" && resource != "free slots") {
      $('#resource').val(resource.replace(/ /g,'_'));
      $('#filter-form').attr("action", home_url);
      submit_filter_form();
    }
  }

  function restrict_minutes(p, resource){
    var start = Math.max(0, Math.floor(x.invert(p[0]))*interval-interval);
    var end = start+interval;
    submit_minutes(start, end, resource);
  }

  function reset_minutes(){
    submit_minutes(0, 1440, $('#resource').val());
  }

  /* The root panel. */
  var vis = d3.select(params.container)
        .append("svg")
        .attr("width", w+50)
        .attr("height", h+70)
        .style("stroke", "#999")
        .style("strokeWidth", 1.0)
        .on("click", update_y_scale)
        .append("g")
        .attr("transform", "translate(40,10)");

  /* X-label */
  vis.append("svg:text")
    .attr("class", "label")
    .attr("dy", h+30)
    .attr("dx", w/2)
    .style("font", "12px open sans")
    .attr("text-anchor", "middle")
    .text("Time of day");

  /* X-axis and ticks. */
  vis.selectAll(".yrule")
    .data(xticks)
    .enter()
    .append("line")
    .attr("class", "yrule")
    .style("stroke", function(d, i){ return (i%24)==0 ? "#999" : "rgba(128,128,128,.2)"; })
  //    .style("stroke-width", function(d, i){ return (i%24)==0 ? 2 : 1; })
    .attr("x1", x)
    .attr("y1", 0)
    .attr("x2", x)
    .attr("y2", h);

  var y_tick_precision;
  var y_ticks_formatter;
  var tooltip_formatter;

  if (params.plot_kind == "memory" || params.plot_kind == "heap") {
    y_ticks_formatter = function(d){ return d3.format(".0f")(d/1000) + "k"; };
    tooltip_formatter = function(d){ return d3.format(".0f")(d/1000) + "k"; };
  }
  else {
    y_tick_precision = params.js_max < 10 ? ".1f" : "0.f";
    y_ticks_formatter = d3.format(y_tick_precision);
    if (params.plot_kind == "time")
      tooltip_formatter = function(d){ return d3.round(d,1) + " ms"; };
    else
      tooltip_formatter = function(d){ return d3.round(d,1); };
  }

  vis.selectAll(".xlabel")
    .data(xticks)
    .enter().append("text")
    .attr("class", "xlabel")
    .attr("x", x)
    .attr("y", h)
    .attr("dx", 0)
    .attr("dy", 12)
    .attr("text-anchor", "middle")
    .style("font", "8px open sans")
    .text(function(d){return (d*interval)/60;});

  /* Y-label */
  vis.append("svg:text")
    .attr("class", "label")
    .attr("dy", -25)
    .attr("dx", -w/2+140)
    .style("font", "12px open sans")
    .attr("text-anchor", "middle")
    .attr("transform", "rotate(270)")
    .text(params.ylabel);

  /* Y-axis and ticks. */

  function draw_grid() {
    var vgrid = vis.selectAll(".xrule").data(y.ticks(10));
    vgrid.enter()
      .append("line")
      .attr("class", "xrule")
      .style("stroke", function(d, i){ return (i==0) ? "#999" : "rgba(128,128,128,.2)"; })
      .attr("y1", y)
      .attr("x1", 0)
      .attr("y2", y)
      .attr("x2", w);
    vgrid.exit().remove();

    var vlabels = vis.selectAll(".ylabel").data(y.ticks(10));
    vlabels.enter().append("text")
      .attr("class", "ylabel")
      .attr("x", 0)
      .attr("y", y)
      .attr("dx", -10)
      .attr("dy", 3)
      .attr("text-anchor", "middle")
      .style("font", "8px open sans")
      .text(y_ticks_formatter);
    vlabels.exit().remove();

    vgrid.transition()
      .duration(zoom_interval)
      .attr("y1", y)
      .attr("y2", y);

    vlabels.transition()
      .duration(zoom_interval)
      .attr("y", y)
      .text(y_ticks_formatter);
  }

  draw_grid();

  /* Legend. */
  vis.selectAll(".legend")
    .data(legend)
    .enter().append("svg:text")
    .attr("class", "legend")
    .attr("x", function(d,i){ return 10+(120*(Math.floor(i))); })
    .attr("y", function(d,i){ return h+50; })
    .on("click", function(d,i){ submit_resource(legend[i]); })
    .style("font", "10px open sans")
    .style("cursor", "pointer")
    .text(String);

  vis.selectAll(".legendmark")
    .data(legend)
    .enter().append("svg:circle")
    .attr("class", "legendmark")
    .attr("transform", "translate(-7,-3)")
    .attr("cx", function(d,i){return 10+(120*(Math.floor(i)));})
    .attr("cy", function(d,i){ return h+50; })
    .attr("r", 4)
    .on("click", function(d,i){ submit_resource(legend[i]); })
    .style("cursor", "pointer")
    .style("stroke", function(d,i){ return colors[i]; })
    .style("fill", function(d,i){ return colors[i]; });

  var request_count_formatter = d3.format((max_request_count < 10) ? ",.1f" : ",.0f");

  vis.selectAll(".rlabel")
    .data([50,25,0])
    .enter()
    .append("text")
    .attr("class", "rlabel")
    .style("font", "10px open sans")
    .attr("text-anchor", "end")
    .attr("y", function(d,i){ return 50-i*25-1 })
    .attr("x", w-1)
    .text(function(d){ return request_count_formatter(y2.invert(d)); });


  var request_area = d3.svg.area()
        .interpolate("cardinal")
        .x(function(d) { return x(d.x+0.5); })
        .y0(function(d) { return y2(d.y0); })
        .y1(function(d) { return y2(d.y + d.y0); });

  var request_data = request_counts.map(function(d,i){ return {x:i, y:d, y0:0};});

  vis.append("rect")
    .style("cursor", "pointer")
    .on("click", reset_minutes)
    .attr("y", 0)
    .attr("x", 0)
    .attr("width", w)
    .attr("height", 50)
    .style("stroke", "none")
    .style("fill", "rgba(128,128,128,.05)");

  var event_tooltip_text = "";

  function mouse_over_event(d, i) {
    var mouseCoords = d3.mouse(this);
    d3.select("#eventLine"+i).style("stroke", "rgba(255,0,0,.5)");
    event_tooltip_text = d[1] + time_suffix(Math.floor(d[0]));
  }

  function mouse_over_out() {
    event_tooltip_text = "";
    d3.selectAll(".eventLine").style("stroke", "rgba(255,0,0,.0)");
  }

  vis.selectAll(".eventLine")
    .data(events)
    .enter()
    .append("line")
    .attr("class", "eventLine")
    .attr("id", function(d,i){ return("eventLine" + i);})
    .style("stroke", "rgba(255,0,0,.0)")
    .style("stroke-width", "3")
    .attr("x1", function(d,i) { return x(d[0] / interval); })
    .attr("y1", 0)
    .attr("x2", function(d,i) { return x(d[0] / interval); })
    .attr("y2", h)
    .on("mouseover", mouse_over_event)
    .on("mousemove", mouse_over_event)
    .on("mouseout",  mouse_over_out);



  /* top x axis */
  vis.append("line")
    .attr("y1", 0)
    .attr("x1", 0)
    .attr("y2", 0)
    .attr("x2", w)
    .style("stroke", "#999")
    .style("fill", "none");

  var request_tooltip_text = "";

  function mouse_over_requests(d, i, n) {
    var p = d3.mouse(n);
    var di = Math.ceil(x.invert(p[0]))-1;
    request_tooltip_text = d3.round(request_counts[di]) + " req/sec" + time_suffix(di*interval);
  }

  vis.selectAll(".request_count")
    .data([request_data])
    .enter().append("path")
    .attr("class", "request_count")
    .style("fill", "rgba(128,128,128,0.2)")
    .style("cursor", "pointer")
    .on("click", function(d,i){ restrict_minutes(d3.mouse(this), $('#resource').val());})
    .on("mouseover", function(d,i){ mouse_over_requests(d, i, this);})
    .on("mousemove", function(d,i){ mouse_over_requests(d, i, this);})
    .on("mouseout", function(d,i){ request_tooltip_text = ""; })
    .style("stroke", "rgba(128,128,128,0.3)")
    .style("stroke-width", 1)
    .attr("d", request_area);

  $('.request_count').tipsy({
    trigger: 'hover',
    follow: 'x',
    offset: 0,
    offsetX: 0,
    offsetY: -20,
    gravity: 's',
    html: false,
    title: function() { return request_tooltip_text; }
  });

  vis.append("rect")
    .attr("y", 0)
    .attr("x", x(selected_slice/interval))
    .attr("width", selected_slice_width)
    .attr("height", 50)
    .attr("display", function(){ return selected_slice>0 ? null : "none"; })
    .style("stroke", "none")
    .style("fill", "rgba(255,0,0,0.3)");

  var area = d3.svg.area()
        .interpolate("cardinal")
        .x(function(d) { return x(d.x+.5); })
        .y0(function(d) { return y(d.y0); })
        .y1(function(d) { return y(d.y+d.y0); });

  function oj(a) {
    return a.map(function(d){
      return d.map(function(d){ return {x:d[0], y:d[1], y0:0}; });
    });
  };

  var odata = oj(data);
  var ldata = d3.layout.stack()(odata);

  var layer_tooltip_text = "";
  var tooltime_formatter = d3.format("02d");

  function time_suffix(n) {
    var h = Math.floor(n / 60);
    var m = Math.floor(n % 60);
    return(" ~ " + tooltime_formatter(h) + ":" + tooltime_formatter(m));
  }

  function mouse_over_layer(d, i, n) {
    var p = d3.mouse(n);
    var di = Math.ceil(x.invert(p[0]))-1;
    var dp = data[i][di];
    layer_tooltip_text = tooltip_formatter(dp[1]) + " " + legend[i] + time_suffix(dp[0]*interval);
  }

  /* The stack layout. */
  vis.selectAll(".layer")
    .data(ldata)
    .enter().append("path")
    .attr("class", "layer")
    .style("fill", function(d,i) { return colors[i]; })
    .style("cursor", function(d,i) { return(legend[i] == "free slots" ? "arrow" : "pointer"); })
    .on("click", function(d,i){ restrict_minutes(d3.mouse(this), legend[i]); })
    .on("mousemove", function(d,i){ mouse_over_layer(d, i, this);})
    .on("mouseover", function(d,i){ mouse_over_layer(d, i, this);})
    .on("mouseout", function(d,i){ layer_tooltip_text = ""; })
    .style("stroke", "none")
    .attr("d", area);

  $('.layer').tipsy({
    trigger: 'hover',
    follow: 'x',
    offset: 0,
    offsetX: 0,
    offsetY: -20,
    gravity: 's',
    html: false,
    title: function() { return layer_tooltip_text; }
  });

  /* GC time */
  if (gc_time != null) {
    var gc_line = d3.svg.line()
          .x(function(d){ return x(d[0]+0.5); })
          .y(function(d){ return y(d[1]); })
          .interpolate("cardinal");

    var gl = vis.append("g")
      .data([gc_time]);

    var da_gc_line = gl.append("path")
          .attr("class", "gc_time")
          .attr("d", gc_line)
          .style("stroke", "rgba(0,0,0,.9)")
          .style("fill", "none");
  }

  var zoomed = true;
  function update_y_scale() {
    var new_max_y = zoomed ? max_y : zoomed_max_y;
    zoomed = !zoomed;
    y.domain([0, new_max_y]).nice();
    redraw();
  }

  function redraw() {
    // Update
    draw_grid();

    vis.selectAll(".layer")
      .transition()
      .duration(zoom_interval)
      .attr("d", area);

    if (gc_time != null) {
      da_gc_line.transition()
        .duration(zoom_interval)
        .attr("d", gc_line);
    };
  }

  vis.selectAll(".event")
    .data(events)
    .enter()
    .append("polygon")
    .attr("class", "event")
    .attr("points", function(d,i) {
      var xCenter = x(d[0] / interval),
          y       = h+5,
          p1      = [xCenter - 4, y],
          p2      = [xCenter + 4, y],
          p3      = [xCenter, y - 5];

      var what = [p1, p2, p3].map(function(point) { return point[0] + "," + point[1]; }).join(" ");
      return what;
    })
    .style("stroke", "rgba(255,0,0,0)")
    .style("fill", "rgba(255,0,0,0.7)")
    .on("mouseover", mouse_over_event)
    .on("mousemove", mouse_over_event)
    .on("mouseout",  mouse_over_out);

  var event_tip_options = {
    trigger: 'hover',
    follow: 'x',
    offset: 0,
    offsetX: 10,
    offsetY: 20,
    gravity: 'w',
    html: false,
    opacity: 0.7,
    title: function() { return event_tooltip_text; }
  };

  $('.event').tipsy(event_tip_options);
  $('.eventLine').tipsy(event_tip_options);
}

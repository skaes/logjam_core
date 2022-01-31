import * as d3 from "d3";

var URI = require('urijs');

function logjam_echart(params) {
  var data = params.data,
      events= params.events,
      url = params.url,
      highlight = params.highlight,
      max_y = params.max_y,
      max_x = params.max_x,
      start = params.start_minute,
      end = params.end_minute,
      h = params.height,
      w = $(params.parent).width(),
      w_r = w - 30,
      x = d3.scaleLinear().domain([0, 1440/2]).range([0, w_r]),
      y = d3.scaleLinear().domain([0, max_y]).range([h, 0]).nice(),

      tooltip_formatter = d3.format(",.2s"),
      tooltip_timeformatter = d3.format("02d");

  var allow_selection = start != null && end != null;

  var vis = d3.select(params.parent)
     .append("svg")
     .attr("width", w)
     .attr("height", events.length == 0 ? h : h+5)
     .style("stroke", "lightsteelblue")
     .style("strokeWidth", 1.0)
     .on("mousedown", mouse_down_event)
     .on("mouseup", mouse_up_event)
     .on("mouseover", mouse_over_event)
     .on("mousemove", mouse_over_event)
     .on("mouseout",  mouse_over_out)
     .style("cursor", function(){ return url ? "pointer" : "arrow"; })
     .on("click", mouse_click_event)
  ;

  vis.selectAll(".rlabel")
    .data([20])
    .enter()
    .append("text")
    .attr("class", "rlabel")
    .style("font", "8px Helvetica Neue")
    .attr("text-anchor", "end")
    .attr("dy", ".75em")
    .attr("x", w-1)
    .text(tooltip_formatter(max_y))
  ;

  var line = d3.line()
        .x(function(d,i) { return x(d[0]); })
        .y(function(d) { return y(d[1]); })
        .curve(d3.curveMonotoneY)
  ;

  var tooltip = $(params.parent + ' svg');
  var tooltip_text = "";

  tooltip.tipsy({
    trigger: 'hover',
    follow: 'x',
    offsetY: -20,
    gravity: 's',
    html: false,
    title: function() { return tooltip_text; }
  });

  function mouse_click_event(e) {
    if (ignore_click) {
      ignore_click = false;
      return;
    }
    if (url) document.location = url;
  }

  function mouse_down_event(e, d) {
    var p = d3.pointer(e);
    var di = Math.ceil(x.invert(p[0]))-1;
    if (allow_selection) {
      mouse_down_start = di;
      mouse_down_end = di;
      start_time_selection(di);
    }
  }

  function mouse_up_event(e, d) {
    e.stopPropagation();
    var p = d3.pointer(e);
    var di = Math.ceil(x.invert(p[0]))-1;
    update_time_selection(di);
    if (allow_selection) {
      finish_time_selection();
    }
  }

  function mouse_over_event(e, d) {
    var p = d3.pointer(e);
    var di = Math.ceil(x.invert(p[0]))-1;
    if (di<0) di=0;
    var xc = data[di];
    var n = 0;
    var m = 2*di;
    var hour = tooltip_timeformatter(Math.floor(m / 60));
    var minute1 = tooltip_timeformatter(Math.floor(m % 60));
    var minute2 = tooltip_timeformatter(Math.floor((m % 60)+1));
    if (xc) {
      n = xc[1];
    }
    tooltip_text = tooltip_formatter((n <= 0) ? 0 : n) + " ~ " + hour + ":" + minute1 + " - " + hour + ":" + minute2 ;
    if (allow_selection) {
      update_time_selection(di);
    }
  }

  function mouse_over_out() {
    tooltip_text = "";
  }

  vis.append("svg:path")
    .attr("d", line(data))
    .style("stroke", highlight ? "#ff0000" : "#006567")
    .style("fill", "none")
  ;

  var xaxis = vis.append("svg:line")
      .style("fill", "#999")
      .style("stroke", "#999")
      .attr("x1", 0)
      .attr("y1", h)
      .attr("x2", w_r)
      .attr("y2", h)
  ;

  if (allow_selection) {
    vis.append("rect")
      .attr("class", "selection")
      .attr("y", 0)
      .attr("height", h)
      .attr("x", x(start/2))
      .attr("width", x(end/2) - x(start/2) + 1)
      .attr("display", (start>0||end<1440) ? null : "none")
      .style("pointer-events", "none")
      .style("stroke", "none")
      .style("fill", "rgba(255,0,0,0.3)");
  }

  vis.selectAll(".event")
    .data(events)
    .enter()
    .append("polygon")
    .attr("class", "event")
    .attr("points", function(d,i) {
      var xCenter = x(d[0] / 2),
          y       = h+5,
          p1      = [xCenter - 4, y],
          p2      = [xCenter + 4, y],
          p3      = [xCenter, y - 5];

      var what = [p1, p2, p3].map(function(point) { return point[0] + "," + point[1]; }).join(" ");
      return what;
    })
    .style("stroke", "rgba(255,0,0,0)")
    .style("fill", "rgba(255,0,0,0.7)")
    .on("mouseover", mouse_over_triangle_event)
    .on("mousemove", mouse_over_triangle_event)
    .on("mouseout",  mouse_over_triangle_out)
  ;

  var event_tooltip_text = "";

  function mouse_over_triangle_event(d, i) {
    event_tooltip_text = d[1].split("\n").map(function(s){return $("<p>").text(s).html();}).join("<br>");
  }

  function mouse_over_triangle_out() {
    event_tooltip_text = "";
  }

  var event_tooltip_options = {
    trigger: 'hover',
    follow: 'x',
    offset: 0,
    offsetX: 10,
    offsetY: 20,
    gravity: 'w',
    html: true,
    title: function() { return event_tooltip_text; }
  };

  if (events.length > 0) {
    $('.event').tipsy(event_tooltip_options);
  }

  function start_time_selection(di) {
    vis.selectAll(".selection")
      .attr("x", x(di))
      .attr("width", 1)
      .attr("display", null);
  }

  var mouse_down_start = -1;
  var mouse_down_end = -1;
  var ignore_click = false;

  function valid_minute(m) {
    if (m < 0)
      return 0;
    else if (m > 1440/2)
      return 1440/2;
    else
      return m;
  }

  // function log_selection() {
  //   console.log("["+mouse_down_start+","+mouse_down_end+"]");
  // }

  function update_time_selection(di) {
    if (mouse_down_start > 0) {
      var m = valid_minute(di);
      mouse_down_end = m;
      if (m >= mouse_down_start) {
        vis.selectAll(".selection")
          .attr("width", x(m) - x(mouse_down_start) + 1);
      } else {
        vis.selectAll(".selection")
          .attr("x", x(m))
          .attr("width", x(mouse_down_start) - x(m) + 1);
      }
    }
  }

  function finish_time_selection() {
    if (mouse_down_start >= 0) {
      if (mouse_down_end >= mouse_down_start)
        select_minutes(mouse_down_start, mouse_down_end);
      else
        select_minutes(mouse_down_end, mouse_down_start);
      mouse_down_start = -1;
      mouse_down_end = -1;
      ignore_click = true;
    }
  }

  function restore_selection() {
    mouse_down_start = -1;
    mouse_down_end = -1;
    vis.selectAll(".selection")
      .attr("x", x(start/2))
      .attr("width", x(end/2) - x(start/2) + 1)
      .attr("display", start>0 ? null : "none");
  }

  function select_minutes(start, end) {
    var uri = new URI(url);
    uri.removeSearch(["start_minute", "end_minute"])
      .addSearch("start_minute", 2*start)
      .addSearch("end_minute", 2*end);
    document.location.href = uri.toString();
  }

  if (allow_selection) {
    $(document).on("mouseup", function() {
      finish_time_selection();
    });
  }
}

function adjustWidthOfFirstTwoColumns() {
  var rows = $('tr.full_stats');
  var nameWidths = rows.map(function(){
    return $(this).children().first().width();
  });
  var maxNameWidth = Math.max.apply(null, nameWidths);
  var numWidths = rows.map(function(){
    return $(this).children().first().next().width();
  });
  var maxNumWidth = Math.max.apply(null, numWidths);
  rows.each(function(){
    var name = $(this).children().first();
    var num = name.next();
    name.width(maxNameWidth);
    num.width(maxNumWidth);
  });
}

window.logjam_echart = logjam_echart;
window.adjustWidthOfFirstTwoColumns = adjustWidthOfFirstTwoColumns;

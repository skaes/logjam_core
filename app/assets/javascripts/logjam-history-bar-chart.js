import * as d3 from "d3";

function logjam_history_bar_chart(data, divid, metric, params, kind) {

  var week_end_colors = params.week_end_colors;
  var week_day_colors = params.week_day_colors;
  var title = metric.replace(/_/g,' ');
  if (title == 'apdex score')
    title = 'apdex score «total time»';
  else if (title == 'papdex score')
    title = 'apdex score «page time»';
  else if (title == 'xapdex score')
    title = 'apdex score «ajax time»';

  function week_day(date) {
    var day = date.getDay();
    return (day > 0 && day < 6);
  }

  function bar_color(date, metric) {
    return (week_day(date) ? week_day_colors[metric] : week_end_colors[metric]);
  }

  function bar_class(date) {
    return (week_day(date) ? "bar weekday" : "bar weekend");
  }

  function is_metric() {
    return kind == "m";
  }

  var margin = {top: 25, right: 80, bottom: 50, left: 80},
      width = document.getElementById('request-history').offsetWidth - margin.left - margin.right - 80,
      height = 150 - margin.top - margin.bottom,

      date_min = d3.min(data, function(d){ return d.date; }),
      date_max = d3.max(data, function(d){ return d.date; }),

      relevant_data = data.filter(function(d){ return is_metric() ? (metric in d) : (metric in d.exception_counts); }),

      data_min = d3.min(relevant_data, function(d){ return is_metric() ? d[metric] : d.exception_counts[metric]; }),
      data_max = d3.max(relevant_data, function(d){ return is_metric() ? d[metric] : d.exception_counts[metric]; });

  if (typeof data_min == 'undefined' || (data_min == 0 && data_max == 0))
    return; // no data

  if (data_min == data_max || metric == "request_count")
    data_min = 0;

  // make space for the last day
  date_max = d3.timeDay.offset(date_max, 1);

  var formatter;

  if (metric.match(/(apdex|xapdex|papdex)_score/i)) {
    data_max = 1.0;
    data_min = d3.min([0.92, data_min]);
    formatter = d3.format(".2f");
  } else if (metric.match(/request_count|errors|warnings|exceptions|five_hundreds/i) || !is_metric()) {
    if (data_max - data_min > 10) {
      formatter = d3.format(",.0d");
    } else {
      formatter = d3.format(",.3r");
    }
  } else if (metric == "availability") {
    formatter = d3.format(",.5r");
  } else {
    formatter = d3.format(",.3r");
  }
  var x = d3.scaleUtc()
      .range([0, width]);

  var y = d3.scaleLinear()
      .range([height, 0]);

  var xAxis = d3.axisBottom(x);

  var yAxis = d3.axisLeft(y)
      .ticks(5)
      .tickFormat(formatter);

  var svg = d3.select("#" + divid).append("svg")
      .attr("width", width + margin.left + margin.right)
      .attr("height", height + margin.top + margin.bottom)
    .append("g")
      .attr("transform", "translate(" + margin.left + "," + margin.top + ")");

  x.domain([date_min, date_max]);
  y.domain([data_min, data_max]).nice(5);

  svg.append("g")
      .attr("class", "x axis")
      .attr("transform", "translate(0," + height + ")")
      .call(xAxis);

  svg.append("g")
      .attr("class", "y axis")
      .call(yAxis)
    .append("text")
      .attr("class", "title")
      // .attr("transform", "rotate(-90)")
      .attr("y", -20)
      .attr("x", 1)
      .attr("dy", ".71em")
      .style("text-anchor", "start")
      .text(title);

  var bar_tooltip_text = "";
  var tooltip_formatter = d3.format(",r");
  var date_formatter = d3.timeFormat("%b %d");
  var exception_formatter = d3.format(",d");
  function mouse_over_bar(d,e) {
    bar_tooltip_text = date_formatter(d.date) + " ~ " +
      (is_metric() ? tooltip_formatter(d[metric]) : exception_formatter(d.exception_counts[metric]));
  }

  var bar_width = x(data[data.length-1].date) - x(data[data.length-2].date) - 0.1;

  svg.selectAll(".bar")
      .data(relevant_data)
    .enter().append("rect")
      .attr("class", function(d){ return bar_class(d.date); })
      .attr("x", function(d) { return x(d.date); })
      .attr("width", bar_width)
      .attr("y", function(d) { return y(is_metric() ? d[metric] : d.exception_counts[metric]); })
      .attr("height", function(d) { return height - y(is_metric() ? d[metric] : d.exception_counts[metric]); })
      .attr("cursor", "pointer")
      .style("fill", function(d) { return bar_color(d.date, metric); })
      .on("click", function(d) { view_date(d.date); })
      .on("mousemove", function(d,i){ mouse_over_bar(d, this); })
      .on("mouseover", function(d,i){ mouse_over_bar(d, this); })
      .on("mouseout", function(d,i){ bar_tooltip_text = ""; });

  $(".bar").tipsy({
    trigger: 'hover',
    follow: 'x',
    offset: 0,
    offsetX: 0,
    offsetY: -20,
    gravity: 's',
    html: false,
    title: function() { return bar_tooltip_text; }
  });
}

window.logjam_history_bar_chart =  logjam_history_bar_chart;

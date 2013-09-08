function logjam_history_bar_chart(data, metric, params) {

  var week_end_colors = params.week_end_colors;
  var week_day_colors = params.week_day_colors;

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

  var margin = {top: 20, right: 20, bottom: 50, left: 150},
      width = 960 - margin.left - margin.right,
      height = 150 - margin.top - margin.bottom,

      data_min = d3.min(data, function(d){ return d[metric]; }),
      data_max = d3.max(data, function(d){ return d[metric]; });

  var formatter = d3.format(",.r");

  var x = d3.time.scale()
      .range([0, width]);

  var y = d3.scale.linear()
      .range([height, 0]);

  var xAxis = d3.svg.axis()
      .scale(x)
      .orient("bottom");

  var yAxis = d3.svg.axis()
      .scale(y)
      .orient("left")
      .ticks(5)
      .tickFormat(formatter);

  var svg = d3.select("#request-history #" + metric).append("svg")
      .attr("width", width + margin.left + margin.right)
      .attr("height", height + margin.top + margin.bottom)
    .append("g")
      .attr("transform", "translate(" + margin.left + "," + margin.top + ")");

  x.domain([data[0].date, data[data.length-1].date]);
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
      .style("text-anchor", "begin")
      .text(metric.replace(/_/g,' '));

  var bar_tooltip_text = "";
  var tooltip_formatter = d3.format(",.3r");
  var date_formatter = d3.time.format("%b %d");
  function mouse_over_bar(d,e) {
    bar_tooltip_text = date_formatter(d.date) + " ~ " + tooltip_formatter(d[metric]);
  }

  svg.selectAll(".bar")
      .data(data)
    .enter().append("rect")
      .attr("class", function(d){ return bar_class(d.date); })
      .attr("x", function(d) { return x(d.date); })
      .attr("width", width/data.length)
      .attr("y", function(d) { return y(d[metric]); })
      .attr("height", function(d) { return height - y(d[metric]); })
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
    opacity: 0.8,
    title: function() { return bar_tooltip_text; }
  });
}

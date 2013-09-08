function logjam_quants_plot(params) {
var
    w = 700,
    h  = 500,
    x = d3.scale.log().domain([params.xmin, params.max_x]).range([0, w]).nice(),
    y = d3.scale.log().domain([1, params.max_y]).range([0, h]).nice(),
    legend = params.legend,
    colors = d3.scale.ordinal().range(params.colors),
    shapes = params.shapes ;

/* The root panel. */
var vis = d3.select("#distribution-plot")
    .append("svg")
     .attr("width", w+100)
     .attr("height", h+100)
     .append("g")
       .attr("transform", "translate(50,50)");

/* Title */
vis.append("svg:text")
    .attr("dy", -10)
    .attr("dx", w/2)
    .attr("text-anchor", "middle")
    .style("font", "16px sans-serif")
    .text(params.title);

/* X-label */
vis.append("svg:text")
    .attr("dy", h+40)
    .attr("dx", w/2)
    .style("font", "12px sans-serif")
    .attr("text-anchor", "middle")
    .text(params.xlabel);

/* X-axis, ticks and tick labels. */
var xaxis = vis.append("svg:line")
    .style("fill", "#999")
    .style("stroke", "#999")
    .attr("x1", 0)
    .attr("y1", h)
    .attr("x2", w)
    .attr("y2", h);

vis.selectAll(".xtick")
     .data(x.ticks())
   .enter().append("line")
     .attr("class", "xtick")
     .attr("x1", x)
     .attr("x2", x)
     .attr("y1", h)
     .attr("y2", function(d,i){ return (i % 9 == 0 || i % 9 == 4) ? h + 10 : h + 5; })
     .style("fill", "#999")
     .style("stroke", "#999");

vis.selectAll(".xlabel")
      .data(x.ticks())
    .enter().append("text")
      .attr("class", "xlabel")
      .attr("x", x)
      .attr("y", h)
      .attr("dy", function(d, i) { return (i % 9 == 0 || i % 9 == 4 ) ? 20 : 15; })
      .attr("text-anchor", "middle")
      .attr("display", function(d,i){ return (i % 9 == 0 || i % 9 == 4) ? null : "none"; })
      .style("font", "8px sans-serif")
      .text(String);


/* Y-label */
vis.append("svg:text")
    .attr("dy", -40)
    .attr("dx", -w/2+100)
    .style("font", "12px sans-serif")
    .attr("text-anchor", "middle")
    .attr("transform", "rotate(270)")
    .text("Number of requests");

var yaxis = vis.append("svg:line")
    .style("fill", "#999")
    .style("stroke", "#999")
    .attr("x1", 0)
    .attr("y1", h)
    .attr("x2", 0)
    .attr("y2", 0);

vis.selectAll(".ytick")
     .data(y.ticks())
   .enter().append("line")
     .attr("class", "ytick")
     .attr("x1", 0)
     .attr("x2", function(d,i){ return (i % 9 == 0 || i % 9 == 4) ? -10 : -5; })
     .attr("y1", y)
     .attr("y2", y)
     .style("fill", "#999")
     .style("stroke", "#999");

vis.selectAll(".ylabel")
      .data(y.ticks())
    .enter().append("text")
      .attr("class", "ylabel")
      .attr("x", 0)
      .attr("y", function(d){ return h-y(d); })
      .attr("dx", function(d, i) { return (i % 9 == 0 || i % 9 == 4 ) ? -20 : -15; })
      .attr("text-anchor", "middle")
      .attr("display", function(d,i){ return (i % 9 == 0 || i % 9 == 4) ? null : "none"; })
      .style("font", "8px sana-serif")
      .text(String);


params.resources.forEach(function(r,i){
  var klazz = "shape" + i;
  vis.selectAll("."+klazz)
    .data(params.data[r])
  .enter().append("svg:path")
    .attr("class", klazz)
    .attr("transform", function(d) { return "translate(" + x(d[0]) + "," + (h-y(d[1])) + ")"; })
    .attr("d", d3.svg.symbol().type(shapes[i]).size(24))
    .style("stroke", colors(i))
    .style("fill", colors(i));
});

/* Legend. */
vis.selectAll(".legend")
    .data(legend)
  .enter().append("svg:text")
    .attr("class", "legend")
    .attr("x", w-60)
    .attr("y", function(d,i){return 20+14*i})
    .style("font", "12px sans-serif")
    .text(String);

vis.selectAll(".legendmark")
    .data(legend)
  .enter().append("svg:path")
    .attr("class", "legendmark")
    .attr("transform", function(d,i){ return "translate(" + (w-70) + "," + (17+14*i) + ")"; })
    .attr("d", function(d,i){ return d3.svg.symbol().type(shapes[i]).size(48).call(); })
    .style("stroke", colors)
    .style("fill", colors);
}

function logjam_simple_pie(params){
  var data = params.data;
  var legend = params.legend;
  var container = params.container;

  /* Sizing and scales. */
  var w = params.w,
      h = params.h,
      r = w / 2,
      s = d3.sum(data),
      a = d3.scale.linear([0, s]).range([0, 2 * Math.PI]),
      color = d3.scale.ordinal().range(params.color);

  /* The root panel. */
  var vis = d3.select(container).append("svg")
        .data([data])
        .attr("width", w)
        .attr("height", h);

  //  .append("g")
  //    .attr("transform", "translate(" + w / 2 + "," + h / 2 + ")");

  /* The pie. */
  var
  donut = d3.layout.pie(),
  arc = d3.svg.arc().innerRadius(0).outerRadius(r);

  var arcs = vis.selectAll("g.arc")
        .data(donut)
        .enter().append("g")
        .attr("class", "arc")
        .style("font", "10px sans-serif")
        .attr("transform", "translate(" + r + "," + r + ")");

  arcs.append("path")
    .attr("fill", function(d, i) { return color(i); })
    .attr("d", arc);

  arcs.append("text")
    .attr("transform", function(d) { return "translate(" + arc.centroid(d) + ")"; })
    .attr("dy", ".35em")
    .attr("text-anchor", "middle")
    .attr("display", function(d) { return d.value/s > .1 ? null : "none"; })
  //    .attr("title", function(d,i){ return legend[i];})
    .text(function(d, i) { return (100*d.value/s).toFixed()+"%"; });
}

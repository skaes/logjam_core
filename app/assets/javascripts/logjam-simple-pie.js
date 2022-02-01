import * as d3 from "d3";

function logjam_simple_pie(params){
  var data = params.data;
  var legend = params.legend;
  var container = params.container;

  /* Sizing and scales. */
  var w = params.w,
      h = params.h,
      r = w / 2,
      s = d3.sum(data),
      a = d3.scaleLinear([0, s]).range([0, 2 * Math.PI]),
      color = d3.scaleOrdinal().range(params.color);

  /* The root panel. */
  var vis = d3.select(container).append("svg")
        .data([data])
        .attr("width", w)
        .attr("height", h);

  if (params.onclick) {
    vis
      .style("cursor", "pointer")
      .on("click", () => window.eval(params.onclick));
  }

  //  .append("g")
  //    .attr("transform", "translate(" + w / 2 + "," + h / 2 + ")");

  /* The pie. */
  var
  donut = d3.pie(),
  arc = d3.arc().innerRadius(0).outerRadius(r);

  var arcs = vis.selectAll("g.arc")
        .data(donut)
        .enter().append("g")
        .attr("class", "arc")
        .style("font", "10px sans-serif")
        .attr("transform", "translate(" + r + "," + r + ")");

  arcs.append("path")
    .attr("fill", (d, i) => color(i))
    .attr("d", arc);

  arcs.append("text")
    .style("cursor", "default")
    .attr("transform", (d) => "translate(" + arc.centroid(d) + ")")
    .attr("dy", ".35em")
    .attr("text-anchor", "middle")
    .attr("display", (d) =>  d.value/s > .1 ? null : "none")
//  .attr("title", (d,i) => legend[i])
    .text((d, i) => (100*d.value/s).toFixed()+"%");
}

window.logjam_simple_pie = logjam_simple_pie;

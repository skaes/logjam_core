import * as d3 from "d3";
import $ from "jquery";

function logjam_quants_plot(params, resource, id, label, scale) {

  function get_height() {
    var height = $('#'+id).height() - 100;
    if (height > 0)
      return height;
    else
      return 500;
  }

  var w = document.getElementById(id).offsetWidth - 120,
      h  = get_height(),
      // x = d3.scaleLog().domain([params.xmin, params.max_x]).range([0, w]).nice(),
      // y = d3.scaleLog().domain([1, params.max_y]).range([0, h]).nice(),
      legend = params.legend,
      color = params.color_map[resource],
      formatter = d3.format(".0s"),
      bucket_values = params.buckets.map((d) => d.bucket)
  ;

  // console.log(resource, id, w, h);
  // console.log(JSON.stringify(bucket_values));
  // console.log(JSON.stringify(params.buckets));

  var x = d3.scaleBand()
        .domain(bucket_values)
        .paddingInner([.01])
        .paddingOuter([.01])
        .range([0, w]);

  var y = (scale == "linear" ? d3.scaleLinear : d3.scaleLog)()
        .domain([.1, params.max_y])
        .range([h,0]);

  /* The root panel. */
  var vis = d3.select('#'+id)
        .append("svg")
        .attr("width", w+100)
        .attr("height", h+100)
        .append("g")
        .attr("transform", "translate(50,50)");

  /* X-label */
  vis.append("svg:text")
    .attr("dy", h+40)
    .attr("dx", w/2)
    .style("font", "12px sans-serif")
    .attr("text-anchor", "middle")
    .attr("text-transform", "capitalize")
    .text(label);

  /* X-axis, ticks and tick labels. */
  var xaxis = vis.append("svg:line")
        .style("fill", "#999")
        .style("stroke", "#999")
        .attr("x1", 0)
        .attr("y1", h)
        .attr("x2", w)
        .attr("y2", h);

  vis.selectAll(".xtick")
    .data(bucket_values)
    .enter().append("line")
    .attr("class", "xtick")
    .attr("x1", (d) => x(d) + x.bandwidth())
    .attr("x2", (d) => x(d) + x.bandwidth())
    .attr("y1", h)
    .attr("y2", h + 5)
    .style("fill", "#999")
    .style("stroke", "#999");

  vis.selectAll(".xlabel")
    .data(bucket_values)
    .enter().append("text")
    .attr("class", "xlabel")
    .attr("x", (d) => x(d) + x.bandwidth())
    .attr("y", h)
    .attr("dy", 17)
    .attr("text-anchor", "middle")
  //.attr("display", function(d,i){ return (i % 9 == 0 || i % 9 == 4) ? null : "none"; })
    .style("font", "8px sans-serif")
    .text(formatter);

  /* Y-label */
  vis.append("svg:text")
    .attr("dy", -40)
    .attr("dx", -h/2)
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
    .attr("x2", -5)
    .attr("y1", y)
    .attr("y2", y)
    .style("fill", "#999")
    .style("stroke", "#999")
    .attr("display", (d,i) => (i > 0 && i%9 == 0) ? null : "none");

  vis.selectAll(".ylabel")
    .data(y.ticks())
    .enter().append("text")
    .attr("class", "ylabel")
    .attr("x", 0)
    .attr("y", (d) => y(d))
    .attr("dx", -17)
    .attr("text-anchor", "middle")
    .attr("display", (d,i) => (i > 0 && i%9 == 0) ? null : "none")
    .style("font", "9px sans-serif")
    .text(formatter);

  function draw_percentile(xp, key, j){
    // percentiles
    var a = [x(xp)+x.bandwidth(), 0];
    var b = [x(xp)+x.bandwidth(), h];

    vis.append("svg:line")
      .style("fill", "rgba(0,0,0,0.5)")
      .style("stroke", "rgba(0,0,0,0.5)")
      .attr("x1", a[0])
      .attr("y1", a[1])
      .attr("x2", b[0])
      .attr("y2", b[1]);

    vis.append("svg:path")
      .attr("transform", "translate(" + a[0] + "," + a[1] + ")")
      .attr("d", d3.symbol().type(d3.symbolCircle).size(64))
      .style("stroke", "#aaa")
      .style("fill", "#aaa");

    vis.append("svg:text")
      .attr("dx", a[0])
      .attr("dy", a[1]-10)
      .attr("text-anchor", "middle")
      .style("font", "10px sans-serif")
      .text(key);

    // vis.append("svg:text")
    //   .attr("dx", a[0]+2)
    //   .attr("dy", a[1]+15+j*10)
    //   .style("font", "10px sans-serif")
    //   .attr("text-anchor", "start")
    //   .text(formatter(xp));
  }

  // console.log(JSON.stringify(params.percentiles));

  function draw_percentiles(){
    var pos = 0;
    var xp90 = params.percentiles[resource].p90;
    var xp95 = params.percentiles[resource].p95;
    var xp99 = params.percentiles[resource].p99;
    if (xp90 != xp95) {
      draw_percentile(xp90, 'p90', pos);
      pos += 1;
    }
    if (xp95 != xp99) {
      draw_percentile(xp95, 'p95', pos);
      pos += 1;
    }
    draw_percentile(xp99, 'p99', pos);
  }
  draw_percentiles();

   // quants
   vis.selectAll(".bar")
    .data(params.buckets)
    .enter().append("rect")
    .attr("class", "bar")
    .style("fill", color)
    .attr("x", (d) => x(d.bucket))
    .attr("y", (d) => y(d[resource]))
    .attr("width", x.bandwidth())
    .attr("height", (d) =>  h - y(d[resource]))
    .on("mousemove", mouse_over_bar)
    .on("mouseover", mouse_over_bar)
    .on("mouseout", mouse_over_out)
  ;

  var tooltip_text = "";
  var tooltip_formatter = d3.format(".2s");

  function mouse_over_bar(e, d) {
    tooltip_text = tooltip_formatter(d[resource]) + " requests";
  }

  function mouse_over_out() {
    tooltip_text = "";
  }

  $(".bar").tipsy({
    trigger: 'hover',
    follow: 'x',
    offset: 0,
    offsetX: 0,
    offsetY: -20,
    gravity: 's',
    html: false,
    title: () => tooltip_text,
  });

}

window.logjam_quants_plot = logjam_quants_plot;

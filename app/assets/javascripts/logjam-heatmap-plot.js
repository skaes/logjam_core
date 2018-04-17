function logjam_heatmap_plot(params) {
  var data      = params.data,
      interval  = params.interval,
      legend    = params.legend,
      container = params.container,
      resource  = params.resource;

  var B = params.data["0"].length;

  function get_height() {
    var enlarged_size = $('#enlarged-plot').height() - 130;
    if (enlarged_size > 0) {
      return enlarged_size;
    }
    var parent_height = $(container).parent('.item').height() - 100;
    return parent_height > 170 ? parent_height : 170;
  }

  var w = (document.getElementById(container.slice(1)).offsetWidth - 60 < 400) ? 626 : document.getElementById(container.slice(1)).offsetWidth - 60,
      h = get_height(),
      xticks = d3.range(25).map(function(h){ return h/interval*60; }),
      x      = d3.scaleLinear().domain([0, 1440/interval]).range([0, w]),
      y      = d3.scaleLinear().domain([0, B]).range([h, 0]).nice(),
      cardWidth = x(2*interval)-x(interval)+1,
      cardHeight = h/B;

  /* tiles */
  var tiles = [];
  for (var key in data)
    tiles = tiles.concat(data[key].map(function(d,i){
      return {
        "minute": +key,
        "bucket": i,
        "value": d
      };
    }).filter(function(e){
      return e.value > 0;
    }));

  if (params.scale == 'logarithmic') {
    tiles.forEach(function(d){
      d.value = Math.log(d.value);
    });
  };

  // console.log(tiles);

  var maxValue = d3.max(tiles, function(d){ return d.value; });
  var maxBucket = d3.max(tiles, function(d){ return d.bucket; });

  //d3.interpolateRgb.gamma(3)("rgb(168, 204, 255)", "rgb(0,0,255)"))

  var colorInterpolator;
  if (resource == 'page_time') {
    colorInterpolator = d3.interpolateGreens;
  } else if (resource == 'ajax_time') {
    colorInterpolator = d3.interpolateReds;
  } else {
    colorInterpolator = d3.interpolateBlues;
  }
  // by not using the full scale, we make low number of requests more visible
  var color = d3.scaleSequential(colorInterpolator)
      .domain([-0.1 * maxValue, maxValue]);

  /* The root panel. */
  var vis = d3.select(params.container)
        .append("svg")
        .attr("width", w+50)
        .attr("height", h+80)
        .style("stroke", "#999")
        .style("strokeWidth", 1.0)
        .append("g")
        .attr("transform", "translate(40,30)");

  /* X-label */
  vis.append("svg:text")
    .attr("class", "label")
    .attr("dy", h+30)
    .attr("dx", w/2)
    .style("font", "12px Helvetica Neue")
    .attr("text-anchor", "middle")
    .text("Time of day");

  /* X-axis and ticks. */
  vis.append("line")
    .attr("class", "xrule")
    .style("stroke", "#999")
    .attr("y1", h)
    .attr("x1", 0)
    .attr("y2", h)
    .attr("x2", w);

  vis.selectAll(".xlabel")
    .data(xticks)
    .enter().append("text")
    .attr("class", "xlabel")
    .attr("x", x)
    .attr("y", h)
    .attr("dx", 0)
    .attr("dy", 12)
    .attr("text-anchor", "middle")
    .style("font", "8px Helvetica Neue")
    .text(function(d){return (d*interval)/60;});

  /* Y-label */
  vis.append("svg:text")
    .attr("class", "label")
    .attr("dy", -30)
    .attr("dx", -h/2)
    .style("font", "12px Helvetica Neue")
    .attr("text-anchor", "middle")
    .attr("transform", "rotate(270)")
    .text("Response Time");

  /* Y-axis and ticks. */
  vis.append("line")
    .attr("class", "yrule")
    .style("stroke", "#999")
    .attr("y1", h)
    .attr("x1", 0)
    .attr("y2", 0)
    .attr("x2", 0);

  var ylabels = ["0ms", "1ms", "3ms", "10ms", "30ms", "0.1s", "0.3s", "1s", "3s", "10s", "30s", "100s",
                 "5m", "17m", "50m", "2.6h", "8.3h", "1.2d", "3.5d"];

  vis.selectAll(".ylabel")
    .data(y.ticks(maxBucket))
    .enter()
    .append("text")
      .attr("class", "ylabel")
      .attr("x", 0)
      .attr("y", y)
      .attr("dx", -3)
      .attr("dy", 0)
      .attr("text-anchor", "end")
      .style("font", "8px Helvetica Neue")
      .text(function(d,i){return ylabels[i];});

  var cards = vis.selectAll(".card")
       .data(tiles, function(d) { return d.minute+':'+d.bucket; });

  cards.append("title");

  cards.enter().append("rect")
    .attr("x", function(d) { return x(d.minute); })
    .attr("y", function(d) { return y(d.bucket+1); })
    .attr("class", "card")
    .attr("width", cardWidth)
    .attr("height", cardHeight)
    .style("stroke-width", 0)
    .style("fill", function(d){ return color(d.value);});

  cards.transition().duration(1000)
    .style("fill", function(d) { return color(d.value); });

  cards.select("title").text(function(d) { return d.value; });

  cards.exit().remove();

}

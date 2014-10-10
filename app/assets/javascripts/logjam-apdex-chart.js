function logjam_apdex_chart(params) {
  var data = params.data;
  var max_y = params.max_y;
  var max_x = params.max_x;
  var min_y = params.min_y;
  var h = params.height;
  var w = 1440/2;
  var x = d3.scale.linear().domain([0, w]).range([0, w]);
  var y = d3.scale.linear().domain([min_y, 1.0]).range([h, 0]).nice();

  var tooltip_formatter = d3.format(",.3r");
  var tooltip_timeformatter = d3.format("02d");

  var vis = d3.select(params.parent)
        .append("svg")
        .attr("width", w)
        .attr("height", h)
        .style("stroke", "lightsteelblue")
        .style("strokeWidth", 1.0)
        .style("fill", "steelblue")
        .on("mouseover", mouse_over_event)
        .on("mousemove", mouse_over_event)
        .on("mouseout",  mouse_over_out)
  ;

  var xaxis = vis.append("svg:line")
        .style("fill", "#999")
        .style("stroke", "#999")
        .attr("x1", 0)
        .attr("y1", h)
        .attr("x2", w)
        .attr("y2", h)
  ;

  var goal = d3.svg.line()
        .x(function(d,i) { return x(d[0]); })
        .y(function(){ return y(0.94); })
  ;

  var area = d3.svg.area()
        .interpolate("monotone")
        .x(function(d,i) { return x(d[0]); })
        .y0(function(d) { return y(0); })
        .y1(function(d) { return y(d[1]); })
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

  function mouse_over_event(d, i) {
    var p = d3.mouse(this);
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
    tooltip_text = tooltip_formatter((n <= 0) ? 0 : n) + " ~ " + hour + ":" + minute1 + "-" + minute2 ;
  }

  function mouse_over_out() {
    tooltip_text = "";
  }

  vis.append("svg:path")
    .attr("d", area(data))
    .style("stroke", "steelblue")
    .style("fill", "lightsteelblue")
  ;

  vis.append("svg:path")
    .attr("d", goal(data))
    .style("stroke", "red")
    .style("fill", "none")
  ;

  vis.selectAll(".rlabel")
    .data([20])
    .enter()
    .append("text")
    .attr("class", "rlabel")
    .style("font", "8px sans-serif")
    .attr("text-anchor", "end")
    .attr("dy", ".75em")
    .attr("x", w-1)
    .text(tooltip_formatter(max_y))
  ;
}

$(document).ready(function() {

  var mobile = navigator.userAgent.match(/iPad|iPhone/i) != null;
  if (!mobile) {
    $("*[title]").tipsy({gravity:"nw", opacity:0.9, offset:10, delayIn:250, delayOut:0, fade:false});
  }
  // bug in some browsers leaves the tooltips open and you can have more than one shown
  $(window).on("beforeunload", function(e){ $(".tipsy").remove(); });

  $('tr.clickable[data-href]').click(function(event) {
    var href = $(this).data("href");
    if (event.which == 2) {
      window.open(href);
    } else {
      document.location.href = href;
    }
    return true;
  });
});

$(document).on('touchstart pointerdown MSPointerDown mousedown', handleTouchStart);
$(document).on('touchmove pointermove MSPointerMove mousemove', handleTouchMove);

var xDown = null,
    yDown = null,
    touchTarget;

function handleTouchStart(event) {
  var evt = event.originalEvent;
  if (evt.touches) {
    xDown = evt.touches[0].clientX;
    yDown = evt.touches[0].clientY;
  } else {
    xDown = evt.clientX;
    yDown = evt.clientY;
  }
    touchTarget = evt.target;
};

function handleTouchMove(event) {
    var evt = event.originalEvent;

    var touchElement = $('#logjam-sidebar, #mobile-trigger');

    if ( ! xDown || ! yDown ) {
        return;
    }

    if (evt.touches) {
      var xUp = evt.touches[0].clientX;
      var yUp = evt.touches[0].clientY;
    } else {
      var xUp = evt.clientX;
      var yUp = evt.clientY;
    }

    var xDiff = xDown - xUp;
    var yDiff = yDown - yUp;

    if ( Math.abs( xDiff ) > Math.abs( yDiff ) ) {/*most significant*/
        if ( xDiff > 0 ) {
            /* left swipe */
          if (touchTarget === touchElement[0] || $.contains(touchElement[0], touchTarget)) {
            $(document).trigger("swipeLeft");
          }
        } else {
            /* right swipe */
          if (touchTarget === touchElement[0]) {
            $(document).trigger("swipeRight");
          }
        }
    } else {
        if ( yDiff > 0 ) {
            /* up swipe */
          if (touchTarget == touchElement[0]) {
            $(document).trigger("swipeUp");
          }
        } else {
            /* down swipe */
          if (touchTarget == touchElement[0]) {
            $(document).trigger("swipeUp");
          }
        }
    }
    /* reset values */
    xDown = null;
    yDown = null;
};

$(function(){
  $(document).on("swipeRight swipeLeft", function(event){
    if (event.type == "swipeRight" && !$("body").hasClass("sidebar-visible")) {
      $("body").addClass("sidebar-visible");
    } else if (event.type == "swipeLeft" && $("body").hasClass("sidebar-visible")) {
      $("body").removeClass("sidebar-visible");
    }
  });

  $("#mobile-trigger").on("click", function(event){
    event.preventDefault();
    $("body").toggleClass("sidebar-visible");
  });
});


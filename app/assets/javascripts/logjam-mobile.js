$(function(){
  $("#mobile-trigger").on("click", function(event){
    event.preventDefault();
    $("body").toggleClass("sidebar-visible");
  });
});


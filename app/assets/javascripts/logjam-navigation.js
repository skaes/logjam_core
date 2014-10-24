/* Toggle sidebar for mobile view */
$(function(){
  $('.sidebar-collapse', '#logjam-sidebar').on('click', function(){
    $('#logjam-sidebar').toggleClass('closed');
  })
});


/* Application chooser */
$(function(){
  $('#auto-refresh').on('click', function(){
    if( $('#auto_refresh').val() == '1' ) {
      $('#auto_refresh').val('0');
      submit_filter_form();
    }
    else {
      $('#auto_refresh').val('1');
      submit_filter_form();
    }
  })

  /* choose the enviroment */
  $('.enviroment-chooser .btn', '#logjam-header').on('mousedown', function(event){
    $('#env').val( $(this).val() );
  });
});

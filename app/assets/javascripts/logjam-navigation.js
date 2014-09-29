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


  /* Application suggest */
  $('.application-suggest').on('focus', function(event) {
    $('.application-chooser').addClass('active');
    $('.dropdown-menu li', '.application-chooser').removeClass('hide');
  });

  $('.application-suggest').on('blur', function(event) {
    setTimeout(function(){
      $('.application-chooser').removeClass('active');
      $('.dropdown-menu li', '.application-chooser').removeClass('active');
    }, 200)
  });


  $('.application-suggest').on('keyup', function(event) {
    $('.dropdown-menu li', '.application-chooser').removeClass('active');
    if( $(this).val().length == 0 ) {
      $('.dropdown-menu li', '.application-chooser').removeClass('hide');
      return;
    }

    var app = $(this).val().toLowerCase();
    $('.dropdown-menu li', '.application-chooser').each(function(){
      if( $(this).data('app').toLowerCase().indexOf(app) === -1 ) {
        $(this).addClass('hide');
      }
      else {
        $(this).removeClass('hide');
      }
    });

    $('.dropdown-menu li:not(.hide)', '.application-chooser').first().addClass('active');

    if( event.keyCode == 40 ) {
      var $current = $('.dropdown-menu li.active', '.application-chooser');
      $current.removeClass('active')
              .next(':not(.hide)').addClass('active');
    }

    if( event.keyCode == 38 ) {
      var $current = $('.dropdown-menu li.active', '.application-chooser');
      $current.removeClass('active')
              .prev(':not(.hide)').addClass('active');
    }

    if( event.keyCode == 13 && $('.dropdown-menu li.active a', '.application-chooser').length > 0 ) {
      location.href = $('.dropdown-menu li.active a', '.application-chooser').attr('href');
    }
  });
});

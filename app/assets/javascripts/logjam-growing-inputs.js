(function($){

  $(function(){
    $('.growing-input').each(function(){
      resize(this);
    })

    $('.growing-input').on('keyup', function(event){
      resize(this);
    })
  })

  var resize = function(item){

    var ghostContainer = $( $(item).data('ghost-container') );
    var value = $(item).val().length !== 0 ? $(item).val() : $(item).attr('placeholder')
    ghostContainer.html( value );

    if( $(item).width() < ghostContainer.width()) {
      $(item).width( ghostContainer.width());
    }
  }

})($)

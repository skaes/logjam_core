/**
 * creates keyboard handles for the most common actions
 */

$(document).on('keydown', function(event){

  console.log(event.keyCode);

  /**
   * search field
   * CTRL + S
   */
  if(event.ctrlKey && event.keyCode === 83) {
    event.preventDefault();
    $('#page-field').focus();
  }

  /**
   * application chooser
   * CTRL + A
   */
  if(event.ctrlKey && event.keyCode === 65 && $('.application-chooser').length > -1) {
    event.preventDefault();

    $('.application-suggest').focus();
  }

  /**
   * date chooser
   * CTRL + D
   */
  if(event.ctrlKey && event.keyCode === 68) {
    event.preventDefault();
    $('#datepicker').focus();
  }

  /**
   * activate / deactivate autorefresh
   * CTRL + R
   */
  if(event.ctrlKey && event.keyCode === 82) {
    event.preventDefault();
    $('#auto-refresh').click();
  }

  /**
   * Go to backend Dashboard
   * CTRL + B
   */
  if(event.ctrlKey && event.keyCode === 66) {
    event.preventDefault();
    $('#auto-refresh').click();
  }

  /**
   * Go to frontend Dashboard
   * CTRL + F
   */
  if(event.ctrlKey && event.keyCode === 70) {
    event.preventDefault();
    $('#auto-refresh').click();
  }

})

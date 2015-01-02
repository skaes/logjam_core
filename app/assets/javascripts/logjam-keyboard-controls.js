/**
 * creates keyboard handles for the most common actions
 */

$(document).on('keydown', function(event){

  // console.log(event.shiftKey);

  /**
   * search field
   * CTRL + S
   */
  if(event.ctrlKey && !event.shiftKey && event.keyCode === 70) {
    event.preventDefault();
    $('.date_clearer').click();
    $('#application-suggest').select2("close");
    $('#namespace-suggest').select2("open");

  }

  /**
   * application chooser
   * CTRL + A
   */
  if(event.ctrlKey && event.shiftKey && event.keyCode === 65 && $('.application-chooser').length > -1) {
    event.preventDefault();
    $('.date_clearer').click()
    $('#namespace-suggest').select2("close");
    $('#application-suggest').select2("open");
  }

  /**
   * date chooser
   * CTRL + D
   */
  if(event.ctrlKey && event.shiftKey && event.keyCode === 68) {
    event.preventDefault();
    $('#namespace-suggest').select2("close");
    $('#application-suggest').select2("close");
    $('#datepicker').focus();
  }

  /**
   * activate / deactivate autorefresh
   * CTRL + R
   */
  if(event.ctrlKey && event.shiftKey && event.keyCode === 82) {
    event.preventDefault();
    $('#auto-refresh').click();
  }

  /**
   * Go to backend Dashboard
   * CTRL + B
   */
  if(event.ctrlKey && event.shiftKey && event.keyCode === 66) {
    event.preventDefault();
    $('#section').val('backend');
    submit_filter_form();
  }

  /**
   * Go to frontend Dashboard
   * CTRL + F
   */
  if(event.ctrlKey && event.shiftKey && event.keyCode === 70) {
    event.preventDefault();
    $('#section').val('frontend');
    submit_filter_form();

  }

})

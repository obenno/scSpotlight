//console.log("yesssss");
//document.body.style.backgroundColor = "skyblue";
$( document ).ready(function() {
    console.log( "ready!" );
    $( "#bottom_box > li > a.nav-link" ).addClass('px-3 py-1');
    // activate bootstrap tooltip
    var tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'));
    var tooltipList = tooltipTriggerList.map(function (tooltipTriggerEl) {
        return new bootstrap.Tooltip(tooltipTriggerEl);
    });
});


// session$sendCustomMessage('show-packer', 'hello packer!')
//Shiny.addCustomMessageHandler('invokeTooltips', (msg) => {
//    
//    //$( document ).ready(function() {
//    console.log( "msg: " + msg );
//        // activate bootstrap tooltip
//    let tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'));
//    let tooltipList = tooltipTriggerList.map(function (tooltipTriggerEl) {
//        return new bootstrap.Tooltip(tooltipTriggerEl);
//    });
//    //});
//
//});

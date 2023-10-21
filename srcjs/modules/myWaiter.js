// These are modified functions of waiter.js to use the spinner
// on box tabs: navset_card_tab()

//import 'waiter';
// waiter was imported by waiter package

// elements to hide on recomputed
var waiterToHideOnRender = new Map();
var waiterToFadeout = new Map();
var waiterToHideOnError = new Map();
var waiterToHideOnSilentError = new Map();

let defaultWaiter = {
  id: null, 
  html: '<div class="container--box"><div class="boxxy"><div class="spinner spinner--1"></div></div></div>', 
  color: '#333e48', 
  hideOnRender: false, 
  hideOnError: false, 
  hideOnSilentError: false, 
  image: null,
  fadeOut: false,
  ns: null,
  //onShown: setWaiterShownInput,
  //onHidden: setWaiterHiddenInput
};

/**
 * Get the dimensions of an element. Used to layer the waiter
 * screen on top of say 'element'.
 * @param  {HTMLElement} element - Element to compute the dimensions.
 * @param  {number} offsetTop - Offset for the top of the dimension.
 * @param  {number} offsetHeight - Offset for the Height dimension.
 */
export const getDimensions = (element, offsetTop = 0, offsetHeight = 0) => {

    let height = element.getBoundingClientRect().height;
    let width = element.getBoundingClientRect().width;

    let paddingTop = window.getComputedStyle(element).paddingTop;
    let paddingBottom = window.getComputedStyle(element).paddingBottom;
    let marginTop = window.getComputedStyle(element).marginTop;
    let marginBottom = window.getComputedStyle(element).marginBottom;
    paddingTop = parseInt(paddingTop);
    paddingBottom = parseInt(paddingBottom);
    marginTop = parseInt(marginTop);
    marginBottom = parseInt(marginBottom);

    let paddingLeft = window.getComputedStyle(element).paddingLeft;
    let paddingRight = window.getComputedStyle(element).paddingRight;
    let marginLeft = window.getComputedStyle(element).marginLeft;
    let marginRight = window.getComputedStyle(element).marginRight;
    paddingLeft = parseInt(paddingLeft);
    paddingRight = parseInt(paddingRight);
    marginLeft = parseInt(marginLeft);
    marginRight = parseInt(marginRight);

    height = height - paddingTop - paddingBottom - marginTop - marginBottom;
    width = width - paddingLeft - paddingRight - marginLeft - marginRight;
    var elementPosition = {
	    width: width,
	    height: height,
	    //top: isNaN(element.offsetTop) ? offsetTop : element.offsetTop + offsetTop,
	    //left: isNaN(element.offsetLeft) ? 0 : element.offsetLeft,
        // force top and left to be 0
        top: 0,
        left: 0,
	};

  return elementPosition;
};

/**
 * Show a waiter screen
 * @function
 * @param  {JSON} params - JSON object of options, see 'defaultWaiter'.
 * @example
 * // defaults
 * show({
 *   id: null, 
 *   html: '<div class="container--box"><div class="boxxy"><div class="spinner spinner--1"></div></div></div>', 
 *   color: '#333e48', 
 *   hideOnRender: false, 
 *   hideOnError: false, 
 *   hideOnSilentError: false, 
 *   image: null,
 *   fadeOut: false,
 *   ns: null,
 *   onShown: setWaiterShownInput,
 *   onHidden: setWaiterHiddenInput
 * });
 */
export const show = (params = defaultWaiter) => {

  // declare
  var dom,
      selector = 'body',
      exists = false;

  // get parent
  if(params.id !== null)
    selector = '#' + params.id;
  
  dom = document.querySelector(selector);
  if(dom == undefined){
    console.log("Cannot find", params.id);
    return ;
  }
  
  // allow missing for testing
  params.hideOnRender = params.hideOnRender || false;

  // set in maps
  waiterToHideOnRender.set(params.id, params);
  waiterToFadeout.set(selector, params.fadeOut);
  waiterToHideOnError.set(params.id, params.hideOnError);
  waiterToHideOnSilentError.set(params.id, params.hideOnSilentError);

  let el = getDimensions(dom); // get dimensions

  // no id = fll screen
  if(params.id === null){
    el.height = window.innerHeight;
    el.width = $("body").width();
  }
  
  // force static if position relative
  // otherwise overlay is completely off
  var pos = window.getComputedStyle(dom, null).position;
  if(pos == 'relative')
    dom.className += ' staticParent';

  // check if overlay exists
  dom.childNodes.forEach((el) => {
    if(el.className === 'waiter-overlay')
      exists = true;
  });

  if(exists){
    console.log("waiter on", params.id, "already exists");
    return;
  }
  
  hideRecalculate(params.id);

  console.log(el);
  let overlay =  createOverlay(params, el);
  // append overlay to dom
  dom.appendChild(overlay);

  // set input
  if(params.onShown != undefined)
    params.onShown(params.id);
  
};

// storage to avoid multiple CSS injections
let hiddenRecalculating = new Map();
/**
 * Hide the recalculate effect from base shiny for a
 * specific element.
 * @param  {string} id - Id of element to hide the 
 * recalculate.
 */
export const hideRecalculate = (id) => {

  if(id === null)
    return ;
  
  if(hiddenRecalculating.get(id))
    return;
  
  hiddenRecalculating.set(id, true);

  var css = '#' + id + '.recalculating {opacity: 1.0 !important; }',
      head = document.head || document.getElementsByTagName('head')[0],
      style = document.createElement('style');

  style.id = id + "-waiter-recalculating";
  if (style.styleSheet){
    style.styleSheet.cssText = css;
  } else {
    style.appendChild(document.createTextNode(css));
  }

  head.appendChild(style);
};

/**
 * Create the waiter overlay to place on top of an element.
 * @function
 * @param  {JSON} params - Parameters see 'defaultWaiter'.
 * @param  {HTMLElement} el - Element to overlay.
 */
export const createOverlay = (params, el) => {
	// create overlay
	let overlay = document.createElement("DIV");
	// create overlay content
	let overlayContent = document.createElement("DIV");
	// insert html
	overlayContent.innerHTML = params.html;
	overlayContent.classList.add("waiter-overlay-content");

	// dynamic position
	if(params.id == null)
		overlay.style.position = "fixed";
	else
		overlay.style.position = "absolute";

	// dynamic dimensions
	overlay.style.height = el.height + 'px';
	overlay.style.width = el.width + 'px';
	overlay.style.top = el.top + 'px';
	overlay.style.left = el.left + 'px';
	overlay.style.backgroundColor = params.color;
	overlay.classList.add("waiter-overlay");
    // Add flex container classes
    overlay.classList.add("html-fill-item");
    overlay.classList.add("html-fill-container");

	if(params.image != null && params.image != ''){
		overlay.style.backgroundImage = "url('" + params.image + "')";
	}

	// either full-screen or partial
	if(params.id !== null) {
		overlay.classList.add("waiter-local");
	} else {
		overlay.classList.add('waiter-fullscreen');
	}

	// append overlay content in overlay
	overlay.appendChild(overlayContent);

	return overlay;
};

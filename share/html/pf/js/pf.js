
function go(template, run) {
  document.forms['f'].run.value=run || document.forms['f'].run.value;
  document.forms['f'].action = template || document.forms['f'].action;
  document.forms['f'].submit();
  return true;
}

function log(stuff)
{
  if( typeof console != 'undefined' )
  {
    console.log(stuff);
  }
}

function getDomPath(el) {
  var stack = [];
  while ( el.parentNode != null ) {
    //        console.log(el.nodeName);
    var sibCount = 0;
    var sibIndex = 0;
    for ( var i = 0; i < el.parentNode.childNodes.length; i++ ) {
      var sib = el.parentNode.childNodes[i];
      if ( sib.nodeName == el.nodeName ) {
        if ( sib === el ) {
          sibIndex = sibCount;
        }
        sibCount++;
      }
    }
    if ( el.hasAttribute('id') && el.id != '' ) {
      stack.unshift('#' + el.id);
      break;
    } else if ( sibCount > 1 ) {
      stack.unshift(el.nodeName.toLowerCase() + ':eq(' + sibIndex + ')');
    } else {
      stack.unshift(el.nodeName.toLowerCase());
    }
    el = el.parentNode;
  }

  return stack.join(' > ');
}

function showhide(whichLayer)
{
  var node2 = document.getElementById(whichLayer);
  var node2_off = document.getElementById(whichLayer+'_label_off');
  var node2_on = document.getElementById(whichLayer+'_label_on');
  $(node2).toggle();
  $(node2_off).toggle();
  $(node2_on).toggle();
}

var waitForFinalEvent = (function () {
  var timers = {};
  return function (callback, ms, uniqueId) {
    if (!uniqueId) {
      uniqueId = "Don't call this twice without a uniqueId";
    }
    if (timers[uniqueId]) {
      clearTimeout (timers[uniqueId]);
    }
    timers[uniqueId] = setTimeout(callback, ms);
  };
})();

function pf_toggle_init()
{
	//    var $em = $("body").css("font-size");

  $('.toggle').off('click.pf_toggle')
    .on('click.pf_toggle',function(e){
			//            log("Click in toggle");
			//            log(e.target);
      
      $ul = $(this).children('ul');

      if(! $.contains($ul[0], e.target)){
        $show = ($ul.css('display') == 'none') ? 1 : 0;
        var $toggle_element = this;

        if( $show )
        {
					/*
            if( $(window).width() < $ul.width()*1.2 ){
            $ul.addClass('wide');
            } else if( $(this).offset().left +
            parseFloat($ul.css('left')) < 0 ) {
            $ul.addClass('wide');
            } else {
            $ul.removeClass('wide');
            }
					*/

					//                    log("toggle show");
          $ul.show();
					/*
            if( $ul.offset().left < 0 ){
            $ul.css('left',0);
            }
					*/
          $(document).off('mouseup.pf_toggle_hide')
            .on('mouseup.pf_toggle_hide',function(e){
							//                            log("in pf_toggle mouseup");
							//                            log( $.contains($toggle_element, e.target) );
              if(! $.contains($toggle_element, e.target)){
								//                                log("Call toggle_hide");
                pf_toggle_hide();
              }
            });

          
          $(this).parents('.menu_group').find('.toggle')
            .off('mouseenter.pf_toggle')
            .on('mouseenter.pf_toggle',function(e){
							//                            log("Hover on menu");
              if( this != $toggle_element )
              {
                $ul.hide();
                $(this).click();
              }
            });
        }
        else
        {
					//                    log("toggle hide");
          $ul.hide();
          $(this).parents('.menu_group')
            .find('.toggle').off('mouseenter.pf_toggle');
        }
      }
    });

  function pf_toggle_hide()
  {
		//        log("pf_toggle_hide");
    $(document).off('mouseup.pf_toggle_hide');
    $('.toggle').each(function(){
      $(this).children('ul').hide();
    });
    
    $('.toggle').off('mouseenter.pf_toggle');
  }

	//    pf_toggle_hide();
  $( '.menu_row .toggle a' ).click(pf_toggle_hide);
  
  log('PF toggle_init');
}

function pf_tree_toggle_init()
{
  $('li .folding').each(function(){
    $li = $(this).parents('li:first');
    $path = getDomPath($li[0]);
    $expand = $.totalStorage($path);
    $ul = $li.children('ul');

		//        log("Found: "+getDomPath($li[0]));
		//        log("  val: "+$expand);

    if( $expand )
    {
      $(this).addClass('expanded');
    }
    else
    {
			//            $li.children('ul').hide();

      $ul.css('height','0px');
    }
  });

  $('li .folding').off('click.pf_tree_toggle').on('click.pf_tree_toggle',function(){pf_tree_toggle(this)});

  log('PF tree_toggle_init');
}

function pf_tree_toggle(t,expand)
{
  log("In toggle");
  $li = $(t).parents('li:first');
  $ul = $li.children('ul');
  
  if( typeof expand == 'undefined' )
  {
		//        $expand = ($ul.css('display') == 'none') ? 1 : 0;
    $expand = ($ul.height() == 0) ? 1 : 0;
  }
  
  $path = getDomPath($li[0]);
  //    log($.totalStorage($path) );
  $.totalStorage($path, $expand);
  
  if( $expand )
  {

    var $oheight = $ul.attr('orig-height');
		//        log('oheight: ' + $oheight);
    if( !$oheight ) {
      $oheight = $ul.css('height', 'auto').height();
			//            log("Set oheight to "+$oheight);
      $ul.css('height','0px');
      $ul.attr('orig-height',$oheight);
    }
		//        log('oheight2: ' + $oheight);

    $ul.animate({'height': $oheight}, 200, function(){$(this).css('height',"")});



		//        $ul.css('height', $(window).height());


		//        $ul.show(200);
		//        $ul.css('height','auto');
    $(t).addClass('expanded');
		//        log('Show '+getDomPath($li[0]));
  }
  else
  {
		//        $ul.hide(200);
		//        $ul.css('height','0px');
    $ul.animate({'height': '0px'}, 200);

    $(t).removeClass('expanded');
		//        log('Hide');
  }

  $ul.parents('ul').removeAttr('orig-height');
}

function pf_menu_height_adjust()
{
  $menu = $('.notifications ul');
  $south = $menu.height() + $menu.offset().top;
  //    log("Menu height: "+$south);
  
  $viewport = $(window).height();
  //    log("Viewport: "+$viewport);
  
  if( $viewport < $south )
  {
    $last = $menu.children('.hide_if_tall').last();
    if( $last.size )
    {
      $last.remove();
      pf_menu_height_adjust();
      //            log("New height: "+($menu.height() + $menu.offset().top));
    }
    
  }
}

function pf_toggle_highlight_init()
{
	$('table.markrow input[type="checkbox"]').change(function(){
	  log('Checkbox highlight toggle');
    if ($(this).is(':checked')){
		  $(this).parent().addClass('highlighted');
		  $(this).parent().siblings().addClass('highlighted');
    } else if($(this).parent().is('.highlighted')) {
		  $(this).parent().removeClass('highlighted');
		  $(this).parent().siblings().removeClass('highlighted');
    }
	});
}

function pf_set_canonical_url()
{
  // Will only work in the same domain
  var title = $('title').text();
  var url = $('link[rel="canonical"]').attr('href');
  history.replaceState({},title, url);
}

function pf_expandable_input_expand()
{
  /*
    log("Height = " + $(this).height());
    log("Inner = " + $(this).innerHeight());
    log("Outer = " + $(this).outerHeight());
    log("Scroll = " + $(this)[0].scrollHeight);
  */
  
  $(this).innerHeight( $(this)[0].scrollHeight );
}

function pf_expandable_input_init()
{
  $('textarea.expandable').off('input.pf_expandable_input')
    .on('input.pf_expandable_input',pf_expandable_input_expand);
}

function pf_boxes_adjust_init()
{
	const el_main = document.getElementById('main');
	const el_boxes = document.getElementById('paraframe_boxes');

	if( !el_main || !el_boxes ) return;
	
	const main_style = window.getComputedStyle(el_main);
	const boxes_style = window.getComputedStyle(el_boxes);

	const main_pad_top = parseFloat(main_style.getPropertyValue('padding-top'));
	const main_pad_width =
				parseFloat(main_style.getPropertyValue('border-left')  ||0) +
				parseFloat(main_style.getPropertyValue('padding-left') ||0) +
				parseFloat(main_style.getPropertyValue('padding-right')||0) +
				parseFloat(main_style.getPropertyValue('border-right') ||0);

	let raf;

	function do_resize(){
		//	console.log('resizing');
		raf = null;
		const boxes_rect = el_boxes.getBoundingClientRect();
		const main_rect = el_main.getBoundingClientRect();
		el_main.style["padding-top"] = (main_pad_top + boxes_rect.height)+"px";
		el_boxes.style.width = (main_rect.width - main_pad_width )+"px";
	}

	const obs_main = new ResizeObserver( els =>{
		//	console.log('main resized');
		if( !raf )  raf = window.requestAnimationFrame(do_resize);
	});

	const obs_boxes = new ResizeObserver( els =>{
		//	console.log('pfboxes resized');
		if( !raf )  raf = window.requestAnimationFrame(do_resize);
	});

	obs_main.observe( el_main );
	obs_boxes.observe( el_boxes );
}

function pf_document_ready()
{
  pf_set_canonical_url();
  
  $("tr.oddeven:odd").addClass("odd");
  $("tr.oddeven:even").addClass("even");

  pf_toggle_highlight_init();
  pf_tree_toggle_init();
  pf_toggle_init();
  pf_expandable_input_init();
	pf_boxes_adjust_init();
	
  $('.notifications').click(pf_menu_height_adjust);


  log('PF js initiated');
};

jQuery(document).ready(pf_document_ready);

log('PF js loaded');

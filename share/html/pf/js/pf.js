
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


(function($) {

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


    function pf_toggle_init()
    {
        $('.toggle').off('click.pf_toggle')
            .on('click.pf_toggle',function(){
                var $toggle_element = this;
                $ul = $(this).children('ul');
                $show = ($ul.css('display') == 'none') ? 1 : 0;
                
                if( $show )
                {
                    //                log("toggle show");
                    $ul.show();
                    $(document).off('mouseup.pf_toggle_hide')
                        .on('mouseup.pf_toggle_hide',function(e){
                            //                        log("in pf_toggle mouseup");
                            //                        log( $.contains($toggle_element, e.target) );
                            if(! $.contains($toggle_element, e.target)){
                                pf_toggle_hide();
                            }
                        });
                }
                else
                {
                    //                log("toggle hide");
                    $ul.hide();
                }

                //            $(this).children('ul').toggle();

            });

        function pf_toggle_hide()
        {
            //        log("pf_toggle_hide");
            $(document).off('mouseup.pf_toggle_hide');
            $('.toggle').each(function(){
                $(this).children('ul').hide();
            });
        }

        log('PF toggle_init');
    }


    function pf_tree_toggle_init()
    {
        $('li .folding').each(function(){
            $li = $(this).parents('li:first');
            $path = getDomPath($li[0]);
            $expand = $.totalStorage($path);
            //        log("Found: "+getDomPath($li[0]));
            //        log("  val: "+$expand);
            if( $expand )
            {
                $(this).addClass('expanded');
            }
            else
            {
                $li.children('ul').hide();
            }
        });

        $('li .folding').off('click.pf_tree_toggle').on('click.pf_tree_toggle',function(){pf_tree_toggle(this)});

        log('PF tree_toggle_init');
    }

    function pf_tree_toggle(t,expand)
    {
        //    log("In toggle");
        $li = $(t).parents('li:first');
        $ul = $li.children('ul');
        
        if( typeof expand == 'undefined' )
        {
            $expand = ($ul.css('display') == 'none') ? 1 : 0;
            
        }
        
        $path = getDomPath($li[0]);
        //    log($.totalStorage($path) );
        $.totalStorage($path, $expand);
        
        if( $expand )
        {
            $ul.show(200);
            $(t).addClass('expanded');
            //        log('Show '+getDomPath($li[0]));
        }
        else
        {
            $ul.hide(200);
            $(t).removeClass('expanded');
            //        log('Hide');
        }
    }

    function pf_menu_height_adjust()
    {
        $menu = $('.notiser ul');
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



    function pf_document_ready()
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
        
        $("tr.oddeven:odd").addClass("odd");
        $("tr.oddeven:even").addClass("even");

        pf_tree_toggle_init();
        pf_toggle_init();

        $('.notifications').click(pf_menu_height_adjust);


        log('PF js initiated');
    };
    
    jQuery(document).ready(pf_document_ready);
}
)(jQuery);

function showhide(whichLayer)
{
    var node2 = document.getElementById(whichLayer);
    var node2_off = document.getElementById(whichLayer+'_label_off');
    var node2_on = document.getElementById(whichLayer+'_label_on');
    $(node2).toggle();
    $(node2_off).toggle();
    $(node2_on).toggle();
}


log('PF js loaded');

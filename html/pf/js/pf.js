
function go(template, run) {
    document.forms['f'].run.value=run || document.forms['f'].run.value;
    document.forms['f'].action = template || document.forms['f'].action;
    document.forms['f'].submit();
    return true;
}
function showhide(whichLayer) {
    if(document.getElementById) {
        var node2 = document.getElementById(whichLayer);
        var style2 = node2.style;
        var tag2 = node2.tagName;
        if( style2.display != 'none' ) {
            style2.display = 'none';
        } else {
            style2.display = '';
        }
    }
}


/*
 * jQuery File Upload Plugin JS Example 8.3.0
 * https://github.com/blueimp/jQuery-File-Upload
 *
 * Copyright 2010, Sebastian Tschan
 * https://blueimp.net
 *
 * Licensed under the MIT license:
 * http://www.opensource.org/licenses/MIT
 */

/*jslint nomen: true, regexp: true */
/*global $, window, blueimp */

$(function () {
    'use strict';

    // Initialize the jQuery File Upload widget:
    $('#fileupload').fileupload({
        // Uncomment the following to send cross-domain cookies:
        //xhrFields: {withCredentials: true},
        //url: 'upload.cgi',
        autoUpload: true,
    });

    // Enable iframe cross-domain access via redirect option:
    $('#fileupload').fileupload(
        'option',
        'redirect',
        window.location.href.replace(
            /\/[^\/]*$/,
            '/cors/result.html?%s'
        )
    );

/*
    $('#fileupload')
        .bind('fileuploadadd', function (e, data) {log('fu add')})
        .bind('fileuploadsubmit', function (e, data) {log('fu submit')})
        .bind('fileuploadsend', function (e, data) {log('fu send')})
        .bind('fileuploaddone', function (e, data) {log('fu done')})
        .bind('fileuploadfail', function (e, data) {log('fu fail')})
        .bind('fileuploadalways', function (e, data) {
            log('fu always');

            // log(data);
            if( data.result )
            {
                $.each(data.result.files, function (index, file){
                    log(index+': '+file.name);
                    //var $thumb = file.thumbnail_url;
                    log(file);
                });
            }
        })
        .bind('fileuploadprogress', function (e, data) {log('fu progress')})
        .bind('fileuploadprogressall', function (e, data) {log('fu progress all')})
        .bind('fileuploadstart', function (e) {log('fu start')})
        .bind('fileuploadstop', function (e) {log('fu stop')})
        .bind('fileuploadchange', function (e, data) {log('fu change')})
        .bind('fileuploadpaste', function (e, data) {log('fu paste')})
        .bind('fileuploaddrop', function (e, data) {log('fu drop')})
        .bind('fileuploaddragover', function (e) {log('fu dragover')})
        .bind('fileuploadchunksend', function (e, data) {log('fu chunk send')})
        .bind('fileuploadchunkdone', function (e, data) {log('fu chunk done')})
        .bind('fileuploadchunkfail', function (e, data) {log('fu chunk fail')})
        .bind('fileuploadchunkalways', function (e, data) {log('fu chunk always')})
        .bind('fileuploaddestroy', function (e, data) {log('fu destroy')})
        .bind('fileuploaddestroyed', function (e, data) {log('fu destroyed')})
        .bind('fileuploadadded', function (e, data) {log('fu added')})
        .bind('fileuploadsent', function (e, data) {log('fu sent')})
        .bind('fileuploadcompleted', function (e, data) {
            log('fu completed');
            log(data);
            $.each(data.files, function (index, file){
                log(index+': '+file.name);
            });
        })
        .bind('fileuploadfailed', function (e, data) {log('fu failed')})
        .bind('fileuploadfinished', function (e, data) {log('fu finished')})
        .bind('fileuploadstarted', function (e) {log('fu started')})
        .bind('fileuploadstopped', function (e) {log('fu stopped')});
*/


    // Load existing files:
    $('#fileupload').addClass('fileupload-processing');
    $.ajax({
        // Uncomment the following to send cross-domain cookies:
        //xhrFields: {withCredentials: true},
        url: $('#fileupload').fileupload('option', 'url'),
        dataType: 'json',
        context: $('#fileupload')[0]
    }).always(function () {
        $(this).removeClass('fileupload-processing');
        log('fu always');

    }).done(function (result) {
        $(this).fileupload('option', 'done')
            .call(this, null, {result: result});
        log('fu done');
    });


});


log('File upload init loaded');

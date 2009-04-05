package Para::Frame::Renderer::FCK::Connector;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2009 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use 5.010;
use strict;
use warnings;
use utf8;
use base 'Para::Frame::Renderer::Custom';

use CGI;

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug throw datadump escape_js );


#######################################################################

sub render_output
{
    my( $rend ) = @_;

    my $req = $rend->{'req'};
    my $q = $req->q;

    debug "Accessing ".$req->page->name;
    foreach my $name ( $q->param )
    {
	debug " $name = ".$q->param($name);
    }


    my $command = $q->param('Command') || '';
    my $resource_type = $q->param('Type') || '';
    my $current_folder = $q->param('CurrentFolder') || '';

    if( $q->param('NewFile') )
    {
	$command = 'FileUpload';
    }


    my $out = "";

    $out .= create_xml_header( $command, $resource_type, $current_folder);


    given( $command )
    {
	when( 'GetFolders' )
	{
	    $out .= get_folders( $resource_type, $current_folder);
	}
	when( 'GetFoldersAndFiles' )
	{
	    $out .= get_folders_and_files( $resource_type, $current_folder );
	}
	when( 'CreateFolder' )
	{
	    $out .= create_folder( $resource_type, $current_folder );
	}
	when( 'FileUpload' )
	{
	    return $rend->file_upload( $resource_type, $current_folder );
	}
	default
	{
	    return send_error(10, "No command given");
	}
    }

    $out .= create_xml_footer();

    warn  $out."\n";

    return \ $out;
}


#######################################################################

sub create_xml_header
{
    my( $command, $resource_type, $current_folder) = @_;

    my $site = $Para::Frame::REQ->site;
    my $dir = $site->get_possible_page( $current_folder );
    debug "XML for URL ".$dir->sysdesig;
    my $url = $dir->path_slash;
    $url =~ s/^\///; # relative path

    my $out = "";

    # Create the XML document header.
    $out .= '<?xml version="1.0" encoding="utf-8" ?>';

    # Create the main "Connector" node.
    $out .= "<Connector command=\"$command\" resourceType=\"$resource_type\">";

    # Add the current folder node.
    $out .= "<CurrentFolder path=\"$current_folder\" ".
      "url=\"$url\" />";
}

#######################################################################

sub create_xml_footer
{
    return "</Connector>";
}


#######################################################################

sub file_upload
{
    my( $rend, $resource_type, $current_folder ) = @_;

    my $req      = $rend->req;
    my $site     = $req->site;
    my $uploaded = $req->uploaded('NewFile');
    my $name     = $req->q->param('NewFile');

    my $destdir = $site->home->get_virtual_dir($current_folder);
    my $dest = $destdir->get_virtual($name);
    my $dest_url = $dest->path;
    $dest_url =~ s/^\///; # relative path

    $resource_type ||= 'unknown';

    debug "Should upload file of type $resource_type to ".$dest->sysdesig;

    $uploaded->save_as($dest);

    return $rend->send_upload_results(0, $dest_url, $dest->name, '');
}


#######################################################################

sub send_upload_results
{
    my( $rend, $error_number, $file_url_in, $file_name_in, $custom_msg_in ) = @_;

    my $file_url = escape_js( $file_url_in );
    my $file_name = escape_js( $file_name_in );
    my $custom_msg = escape_js( $custom_msg_in );

    $rend->{'mimestr'} = 'text/html';

    my $out = <<EOF;
<script type="text/javascript">
(function(){var d=document.domain;while (true){try{var A=window.parent.document.domain;break;}catch(e) {};d=d.replace(/.*?(?:\\.|\$)/,'');if (d.length==0) break;try{document.domain=d;}catch (e){break;}}})();
window.parent.OnUploadCompleted($error_number,"$file_url","$file_name","$custom_msg");
</script>
EOF

    debug "Returning $out";

    return \ $out;
}


#######################################################################

sub create_folder
{
    die "FIXME";
}


#######################################################################

sub get_folders
{
    my( $resource_type, $current_folder ) = @_;

    my $req = $Para::Frame::REQ;
    my $site = $req->site;

    # Map the virtual path to the local server path.
    my $sys_dir = $site->get_possible_page( $current_folder );


    my $out = "";

    unless( $sys_dir->is_dir )
    {
	die "$sys_dir is not a dir";
    }

    $out .= '<Folders>';
    foreach my $dir ( $sys_dir->dirs->as_array )
    {
	my $name = CGI::escapeHTML($dir->name);
	$out .= "<Folder name=\"$name\" />" ;
    }
    $out .= '</Folders>';

    return $out;
}


#######################################################################

sub get_folders_and_files
{
    my( $resource_type, $current_folder ) = @_;

    my $req = $Para::Frame::REQ;
    my $site = $req->site;

    # Map the virtual path to the local server path.
    my $sys_dir = $site->get_possible_page( $current_folder );


    my $out = "";

    unless( $sys_dir->is_dir )
    {
	die "$sys_dir is not a dir";
    }

    $out .= '<Folders>';
    foreach my $dir ( $sys_dir->dirs->as_array )
    {
	my $name = CGI::escapeHTML($dir->name);
	$out .= "<Folder name=\"$name\" />" ;
    }
    $out .= '</Folders>';

    $out .= '<Files>';
    foreach my $file ( $sys_dir->files->as_array )
    {
	$file->initiate;
	my $name = CGI::escapeHTML($file->name);
	my $size = int( $file->{'size'} / 1024 );
	$out .= "<File name=\"$name\" size=\"$size\" />" ;
    }
    $out .= '</Files>';

    return $out;
}


#######################################################################

sub create_folder
{
    die "FIXME";
}


#######################################################################

sub send_error
{
    my( $number, $text_in ) = @_;

    debug "SENDING ERROR $number $text_in";

    my $text = CGI::escapeHTML( $text_in );

    my $out = "";
    # Create the XML document header
    $out .=  '<?xml version="1.0" encoding="utf-8" ?>' ;
    $out .= '<Connector><Error number="$number" text="$text" /></Connector>' ;
    return \ $out;
}


#######################################################################

sub set_ctype
{
    my( $rend, $ctype ) = @_;

    my $mimestr = $rend->{'mimestr'} || 'text/xml';

    $ctype->set_charset('UTF-8');
    $ctype->set_type($mimestr);
    return $ctype;
}


#######################################################################


1;

__END__


    * ERROR_NONE - 0
    * ERROR_CUSTOM_ERROR - 1
    * ERROR_INVALID_COMMAND - 10
    * ERROR_TYPE_NOT_SPECIFIED - 11
    * ERROR_INVALID_TYPE - 12
    * ERROR_INVALID_NAME - 102
    * ERROR_UNAUTHORIZED - 103
    * ERROR_ACCESS_DENIED - 104
    * ERROR_INVALID_REQUEST - 109
    * ERROR_UNKNOWN - 110
    * ERROR_ALREADY_EXIST - 115
    * ERROR_FOLDER_NOT_FOUND - 116
    * ERROR_FILE_NOT_FOUND - 117
    * ERROR_UPLOADED_FILE_RENAMED - 201
    * ERROR_UPLOADED_INVALID - 202
    * ERROR_UPLOADED_TOO_BIG - 203
    * ERROR_UPLOADED_CORRUPT - 204
    * ERROR_UPLOADED_NO_TMP_DIR - 205
    * ERROR_UPLOADED_WRONG_HTML_FILE - 206
    * ERROR_CONNECTOR_DISABLED - 500
    * ERROR_THUMBNAILS_DISABLED - 501

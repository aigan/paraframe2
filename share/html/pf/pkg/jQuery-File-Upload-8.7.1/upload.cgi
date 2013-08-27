#!/usr/bin/perl

use 5.010;
use strict;
use warnings;

use jQuery::File::Upload;

$| = 1;

#sleep 20;
#print "Content-type: text/plain\n\n";
#say "Hello";
#exit;
my $udir = '/tmp/pf-upload';

unless( -d $udir )
{
    mkdir $udir;
}


#simplest implementation
my $j_fu = jQuery::File::Upload->new;
$j_fu->upload_url_base('http://jonas.ls1.se/~joli/test/jQuery-File-Upload-8.7.1/files');
$j_fu->script_url('upload.cgi');
$j_fu->upload_dir($udir);
$j_fu->handle_request;
$j_fu->print_response;

#print $j_fu->output//'';

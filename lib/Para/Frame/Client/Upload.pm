package Para::Frame::Client::Upload;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2013 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Para::Frame::Client::Upload - The client for uploads

=cut

use 5.010;
use strict;
use warnings;
use utf8; # Using 'Ã' in deunicode()

use Encode; # encode decode
use Apache2::RequestRec;
use Apache2::Connection;
use Apache2::Const -compile => qw( DECLINED DONE );

use jQuery::File::Upload;

use Para::Frame::Reload;

our $r;
our $DEBUG = 0;


=head1 DESCRIPTION

Using pf/share/html/pf/pkg/jQuery-File-Upload-8.7.1

=cut


##############################################################################

sub handler
{
    ( $r ) = @_;
    my $s = Apache2::ServerUtil->server;

    my $dirconfig = $r->dir_config;
    my $method = $r->method;

    if( $dirconfig->{'site'} and $dirconfig->{'site'} eq 'ignore' )
    {
	return Apache2::Const::DECLINED;
    }

    $| = 1;


    #$r->content_type('text/plain');

    my $ubase = $r->unparsed_uri;
    $ubase =~ s(/pf/upload/)(/files);

    my $sr = $r->lookup_uri($ubase);
    my $udir = $sr->filename;

    $s->log_error( "Uploading to $udir" ) if $DEBUG;

    #sleep 20;
    #print "Content-type: text/plain\n\n";
    #say "Hello";
    #say $ubase;
    #say $udir;
    #return Apache2::Const::DONE;

    #simplest implementation
    my $j_fu = jQuery::File::Upload->new;
    $j_fu->upload_url_base( $ubase );
    $j_fu->script_url( $r->unparsed_uri );
    $j_fu->upload_dir( $udir );
    $j_fu->handle_request;

    my $file = $j_fu->filename;

    $s->log_error( $j_fu->filename ) if $DEBUG;

    chmod 0660, "$udir/$file";
    chmod 0660, "$udir/thumb_$file" if -r "$udir/thumb_$file";

    my $cfn = $j_fu->client_filename;
#    $s->log_error("cfn: $cfn ".validate_utf8(\$cfn));
#    $s->log_error("Length: ".length($cfn));

#    my $dcfn = decode("UTF-8", $cfn, Encode::FB_QUIET);
#    my $res = utf8::decode($cfn);
#    $s->log_error("cfn: $dcfn ".validate_utf8(\$dcfn));
#    $s->log_error("Length: ".length($dcfn));
#    $cfn = $dcfn;

    my $dcfn = "";
    while( length $cfn )
    {
        $dcfn .= decode("UTF-8", $cfn, Encode::FB_QUIET);
        $dcfn .= substr($cfn, 0, 1, "") if length $cfn;
    }


    $j_fu->client_filename($dcfn);
    $j_fu->_generate_output;

    my $output = $j_fu->output;
#    $s->log_error("output:\n$output");
    $r->print( $output );
    #$j_fu->print_response;

    $s->log_error("$$: Done") if $DEBUG;

    return Apache2::Const::DONE;
}
#print $j_fu->output//'';

##############################################################################

sub validate_utf8
{
    if( utf8::is_utf8(${$_[0]}) )
    {
	if( utf8::valid(${$_[0]}) )
	{
	    if( ${$_[0]} =~ /Ã/ )
	    {
		return "DOUBLE-ENCODED utf8";
	    }
	    else
	    {
		return "valid utf8";
	    }
	}
	else
	{
	    return "as INVALID utf8";
	}
    }
    else
    {
	if( ${$_[0]} =~ /Ã/ )
	{
	    return "UNMARKED utf8";
	}
	else
	{
	    return "NOT Marked as utf8";
	}
    }
}

##############################################################################

1;


=head1 AUTHOR

Jonas Liljegren E<lt>jonas@paranormal.seE<gt>

=head1 SEE ALSO

L<Para::Frame>, L<Apache>

=cut

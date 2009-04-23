package Para::Frame::Logging;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2006-2009 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Para::Frame::Logging - Logging class

=cut

use strict;

use List::Util qw( max );

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug );

our %WATCH;


=head1 DESCRIPTION

=cut


##############################################################################

=head2 new

=cut

sub new
{
    my( $this ) = @_;

    my $class = ref($this) || $this;

    return bless {}, $class;
}


##############################################################################

=head2 watchlist

  Para::Frame::Debug->watchlist()

=cut

sub watchlist
{
    return \%WATCH;
}


##############################################################################

=head2 debug_data

=cut

sub debug_data
{
    my( $log ) = @_;

    my $req = $Para::Frame::REQ;
    my $resp = $req->response_if_existing;

    my $out = "";
    my $reqnum = $req->{'reqnum'};
    $out .= "This is request $reqnum\n";

    $out .= $req->session->debug_data;

    if( $req->is_from_client )
    {
	if( my $orig_resp = $req->original_response )
	{
	    my $orig_url_path = $orig_resp->page->url_path_slash;
	    $out .= "Orig url: $orig_url_path\n";
	}
	else
	{
	    $out .= "No orig url found\n";
	}

	if( my $browser = $req->env->{'HTTP_USER_AGENT'} )
	{
	    $out .= "Browser is $browser\n";
	}

	if( $resp )
	{
	    my $page = $resp->page;

	    if( my $referer = $req->referer_path )
	    {
		$out .= "Referer is $referer\n"
	    }

	    if( my $redirect = $page->{'redirect'} )
	    {
		$out .= "Redirect is set to $redirect\n";
	    }

	    if( my $errtmpl = $page->{'error_template'} )
	    {
		$out .= "Error template is set to $errtmpl\n";
	    }

	    if( $page->{'in_body'} )
	    {
		$out .= "We have already sent the http header\n"
	    }
	}
	else
	{
	    $out .= "The request has no response set\n";
	}

    }

    if( my $chldnum = $req->{'childs'} )
    {
	$out .= "This request waits for $chldnum children\n";

	foreach my $child ( values %Para::Frame::CHILD )
	{
	    my $creq = $child->req;
	    my $creqnum = $creq->{'reqnum'};
	    my $cclient = $creq->client;
	    my $cpid = $child->pid;
	    $out .= "  Req $creqnum $cclient has a child with pid $cpid\n";
	}
    }

    if( $req->{'in_yield'} )
    {
	$out .= "This request is in yield now\n";
    }

    if( $req->{'wait'} )
    {
	$out .= "This request waits for something\n";
    }

    if( my $jobcnt = @{ $req->{'jobs'} } )
    {
	$out .= "Has $jobcnt jobs\n";
	foreach my $job ( @{ $req->{'jobs'} } )
	{
	    my( $cmd, @args ) = @$job;
	    $out .= "  $cmd with args @args\n";
	}
    }

    if( my $acnt = @{ $req->{'actions'} } )
    {
	$out .= "Has $acnt a\n";
	foreach my $action ( @{ $req->{'actions'} } )
	{
	    $out .= "  $action\n";
	}
    }

    if( $req->result )
    {
	$out .= "Result:\n".$req->result->as_string;
    }

    return $out;
}

##############################################################################

=head2 at_level

  $this->at_level( $level )

Returns the logging level for the caller function, or, if missing, the
global debuggling level subtracted with the given level, but at least
0.

=cut

sub at_level
{
    my( $this, $level ) = @_;

    my $debug = $Para::Frame::Logging::WATCH{(caller(1))[3]};

    unless( $debug )
    {
	$debug = $Para::Frame::DEBUG  || 0;
	$debug -= $level;
    }

    return max($debug,0);
}


##############################################################################

=head2 this_level

  this_level()

  this_level( $level )

=cut

sub this_level
{
    my( $this, $level ) = @_;

    if( $level )
    {
	return $Para::Frame::Logging::WATCH{(caller(1))[3]} = $level;
    }
    else
    {
	return $Para::Frame::Logging::WATCH{(caller(1))[3]};
    }
}


##############################################################################

1;

=head1 SEE ALSO

L<Para::Frame>

=cut

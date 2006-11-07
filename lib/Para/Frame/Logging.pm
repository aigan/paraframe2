#  $Id$  -*-cperl-*-
package Para::Frame::Logging;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Logging class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2006 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::Logging - Logging class

=cut

use strict;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug );

our %WATCH;


=head1 DESCRIPTION

=cut

sub new
{
    my( $this ) = @_;

    my $class = ref($this) || $this;

    return bless {}, $class;
}

=head2 watchlist

  Para::Frame::Debug->watchlist()

=cut

sub watchlist
{
    return \%WATCH;
}

sub debug_data
{
    my( $log ) = @_;

    my $req = $Para::Frame::REQ;
    my $page = $req->page;

    my $out = "";
    my $reqnum = $req->{'reqnum'};
    $out .= "This is request $reqnum\n";

    $out .= $req->session->debug_data;

    if( $req->is_from_client )
    {
	my $orig_url_path = $req->original_response->page->url_path_slash;
	$out .= "Orig url: $orig_url_path\n";

	if( my $redirect = $page->{'redirect'} )
	{
	    $out .= "Redirect is set to $redirect\n";
	}

	if( my $browser = $req->env->{'HTTP_USER_AGENT'} )
	{
	    $out .= "Browser is $browser\n";
	}

	if( my $errtmpl = $page->{'error_template'} )
	{
	    $out .= "Error template is set to $errtmpl\n";
	}

	if( my $referer = $req->referer )
	{
	    $out .= "Referer is $referer\n"
	}

	if( $page->{'in_body'} )
	{
	    $out .= "We have already sent the http header\n"
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

}


1;

=head1 SEE ALSO

L<Para::Frame>

=cut

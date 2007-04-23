#  $Id$  -*-cperl-*-
package Para::Frame::Action::wait_for_req;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se action for getting Apache info in
#   Para::Frame::Request->send_code()
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2006 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;

use Para::Frame::Utils qw( debug );

our $CNT;

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;

    my $client = $q->param('req');

    my $oreq = $Para::Frame::REQUEST{ $client };

    unless( $oreq )
    {
	die "Could not find $client in Para::Frame::REQUEST hash!!!\n";
    }

    $oreq->{'active_reqest'} = $req;
    debug "Req $oreq->{reqnum} has active_reqest $req->{reqnum}";

    $req->{'wait'} ++;
    debug "Req $req->{reqnum} waits for $req->{'wait'} things";

    # Give a short quick response
    #
    my $page = "Done";
    $req->response->set_content( \$page );

    debug "Now waiting for release";

    return "";
}

1;


=head1 NAME

Para::Frame::Action::wait_for_req - For internal pseudorequests

=cut

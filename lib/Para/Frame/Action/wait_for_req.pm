#  $Id$  -*-perl-*-
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
#   Copyright (C) 2005 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;
use Data::Dumper;

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
	warn "Could not find $client!!!\n";
	die;
    }

    $oreq->{'active_reqest'} = $req;

    $req->{'wait'} ++;

    # Give a short quick response
    #
    my $page = "Done";
    $req->{'renderer'} = sub
    {
	$req->{'page_content'} = \$page;
	$req->{'page_sender'} = 'bytes';
    };

    debug "Now waiting for release";

    return "";
}

1;

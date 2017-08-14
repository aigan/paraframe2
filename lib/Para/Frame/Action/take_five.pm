package Para::Frame::Action::take_five;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2017 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.012;
use warnings;

# For testing purposes

sub handler
{
    my( $req ) = @_;

    my $count = $req->q->param('count') || 5;

    for(1..$count)
    {
	sleep 1;
	$req->yield;
#	$req->note("Round $_");
    }


    return "Took five";
}

1;

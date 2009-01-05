#  $Id$  -*-cperl-*-
package Para::Frame::Action::take_five;

use strict;

# For testing purposes

sub handler
{
    my( $req ) = @_;

    for(1..15)
    {
	sleep 1;
	$req->yield;
#	$req->note("Round $_");
    }


    return "Took five";
}

1;

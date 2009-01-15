#  $Id$  -*-cperl-*-
package Para::Frame::Action::take_five;

use strict;

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

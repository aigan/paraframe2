#  $Id$  -*-cperl-*-
package Para::Frame::Action::test_ipc;

use strict;

sub handler
{
    my( $req ) = @_;

    my $daemon = "karl.rit.se:7791";

    my $res = $req->send_to_daemon($daemon, 'run_action');

    my $change = $req->change;
    $change->note("Contacted $daemon: $res");

    return "Test done";
}

1;

package Para::Frame::Action::test_ipc;

use 5.010;
use strict;
use warnings;

sub handler
{
    my( $req ) = @_;

    my $daemon = "karl.rit.se:7791";

    my $res = $req->talk_to_daemon($daemon, 'run_action');

    my $change = $req->change;
    $change->note("Contacted $daemon: $res");

    return "Test done";
}

1;

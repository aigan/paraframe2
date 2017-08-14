package Para::Frame::Action::test_ipc;
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

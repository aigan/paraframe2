package Para::Frame::Action::sleep;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2015-2017 Jonas Liljegren.  All Rights Reserved.
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

    $req->require_root_access;

    sleep 20;

    return "Yawn";
}

1;

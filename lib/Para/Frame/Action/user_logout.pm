#  $Id$  -*-perl-*-
package Para::Frame::Action::user_logout;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se user logout action
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;

sub handler
{
    my( $req ) = @_;

    $Para::Frame::U->logout;

    return "Du har nu loggat ut\n";
}

1;

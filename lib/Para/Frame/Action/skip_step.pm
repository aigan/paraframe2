#  $Id$  -*-perl-*-
package Para::Frame::Action::skip_step;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se skip step in route
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

    my $route = $req->s->route;

    $route->skip_step;

    return "Ångrar ett steg";
}

1;

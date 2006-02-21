#  $Id$  -*-perl-*-
package Para::Frame::Action::remove_step;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se remove top step in route
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2006 Jonas Liljegren.  All Rights Reserved.
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

    $route->remove_step;

    return "Tar bort ett steg";
}

1;


=head1 NAME

Para::Frame::Action::remove_step - removes a step from the route

=cut

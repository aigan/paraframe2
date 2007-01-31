#  $Id$  -*-cperl-*-
package Para::Frame::Action::next_step;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se take next step in route
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
    my $break_path = $req->q->param('break_path');
    $route->get_next($break_path);

    return $req->change->report;
}

1;


=head1 NAME

Para::Frame::Action::next_step - Gets the next step from the route

=cut

#  $Id$  -*-cperl-*-
package Para::Frame::Action::skip_step;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2008 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;


=head1 NAME

Para::Frame::Action::skip_step - Skips a step in the route

=cut

sub handler
{
    my( $req ) = @_;

    my $route = $req->s->route;

    $route->skip_step;

    return "Reverting one step";
}

1;

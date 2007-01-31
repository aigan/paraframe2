#  $Id$  -*-cperl-*-
package Para::Frame::Action::mark;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se put current place in route
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2007 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;

use Para::Frame::Utils qw( uri store_params);

#
# See Para::Frame::Route
#

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $route = $req->s->route;

    my @run = $q->param('run');
    $q->delete('run');

    $route->bookmark( $req->referer_with_query );

    $q->param('run', grep {$_ ne 'mark'} @run );

    return "";
}

1;


=head1 NAME

Para::Frame::Action::mark - bookmarks a page for the route

=cut

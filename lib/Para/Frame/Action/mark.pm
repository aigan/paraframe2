#  $Id$  -*-perl-*-
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
#   Copyright (C) 2004 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;
use Para::Frame::Utils qw( referer );

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $route = $req->s->route;

    my @run = $q->param('run');
    $q->delete('run');

    $route->bookmark( referer() );

    $q->param('run', grep {$_ ne 'mark'} @run );
    
    return "";
}

1;

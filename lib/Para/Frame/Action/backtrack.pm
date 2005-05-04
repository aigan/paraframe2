#  $Id$  -*-perl-*-
package Para::Frame::Action::backtrack;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se backtrack action
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
use CGI;

sub handler
{
    my( $req ) = @_;

    my $route = $req->s->route;

    # Flag for backtracking
    $req->{'q'} = CGI->new('backtrack');
    warn "  !! Setting query string to ".$req->q->query_string."\n";
    return "";
}

1;

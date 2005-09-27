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

use Para::Frame::Utils qw( store_params add_params );

sub handler
{
    my( $req ) = @_;

    # Flag for backtracking

    my $state = store_params();

    $req->{'q'} = CGI->new('backtrack');
    
    add_params( $state );

    warn "  !!Setting query string to ".$req->q->query_string."\n";
    return "";
}

1;

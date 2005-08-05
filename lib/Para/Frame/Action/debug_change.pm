#  $Id$  -*-perl-*-
package Para::Frame::Action::debug_change;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se change debug level
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

    my $q = $req->q;
    my $s = $req->s;


    my $level = $q->param('debuglevel');
    $level = $s->{'debug'} unless defined $level;

    warn "  Request to change debug level from $s->{'debug'} to $level\n";

    if( $level != $s->{'debug'} )
    {
	$Para::Frame::DEBUG = $s->{'debug'} = $level;
	return "Changed session debug level to $level";
    }
    
    return "";
}

1;

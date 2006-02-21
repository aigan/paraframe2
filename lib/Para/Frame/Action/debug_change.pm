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

    my $q = $req->q;
    my $s = $req->s;


    my $level = $q->param('debuglevel');
    $level = $s->{'debug'} unless defined $level;

    my $txt = "";

    if( $level != $s->{'debug'} )
    {
	$Para::Frame::DEBUG = $s->{'debug'} = $level;
	$txt .= "Changed session debug level to $level\n";
    }

    my $global_level = $q->param('debuglevel-global');
    $global_level = $Para::Frame::CFG->{'debug'} unless defined $global_level;

    if( $global_level != $Para::Frame::CFG->{'debug'} )
    {
	$Para::Frame::CFG->{'debug'} = $global_level;
	$txt .= "Changed global debug level to $global_level\n";
    }
    
    return $txt;
}

1;


=head1 NAME

Para::Frame::Action::debug_change - changing the debug level

=cut

#  $Id$  -*-perl-*-
package Para::Frame::Action::server_reload;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se reload the paraframe server
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;

use Para::Frame::Utils qw( throw );

sub handler
{
    my( $req ) = @_;

    my $u = $Para::Frame::U;

    unless( $u->level >= 42 )
    {
	throw("denied", "Neeeeej! Vill inte!");
    }

    warn "Reloading server by request!\n";

    $Para::Frame::TERMINATE = 'HUP';

    return "Reloading server...";
}

1;

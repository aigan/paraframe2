#  $Id$  -*-perl-*-
package Para::Frame::Action::server_reload;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2008 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;

use Para::Frame::Utils qw( throw );

=head1 NAME

Para::Frame::Action::server_reload - Reloads the daemon

=cut

sub handler
{
    my( $req ) = @_;

    my $u = $Para::Frame::U;

    unless( $u->has_root_access )
    {
	throw("denied", "Neeeeej! Vill inte!");
    }

    $Para::Frame::TERMINATE = 'HUP';

    return "Reloading server...";
}

1;

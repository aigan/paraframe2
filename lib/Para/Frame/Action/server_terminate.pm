#  $Id$  -*-cperl-*-
package Para::Frame::Action::server_terminate;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se stop the paraframe server
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

use Para::Frame::Utils qw( throw debug );

use Para::Frame::Widget qw( confirm_simple );

sub handler
{
    my( $req ) = @_;

    my $u = $Para::Frame::U;

    unless( $u->has_root_access )
    {
	throw("denied", "Neeeeej! Vill inte!");
    }

    confirm_simple();

    $Para::Frame::TERMINATE = 'TERM';

    return "Terminating server...";
}

1;


=head1 NAME

Para::Frame::Action::server_terminate - Terminates the daemon

=cut

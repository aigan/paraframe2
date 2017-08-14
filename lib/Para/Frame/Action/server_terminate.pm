package Para::Frame::Action::server_terminate;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2017 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.012;
use warnings;

use Para::Frame::Utils qw( throw debug );

use Para::Frame::Widget qw( confirm_simple );


=head1 NAME

Para::Frame::Action::server_terminate - Terminates the daemon

=cut

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

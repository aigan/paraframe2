package Para::Frame::Action::session_vars_update;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2014 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.010;
use strict;
use warnings;

=head1 NAME

Para::Frame::Action::user_logou - For logging out

=cut

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $session = $req->session;

    my @varlist = split /\s*,\s*/, $q->param('session_vars_update');

    foreach my $key ( @varlist )
    {
        $session->var_update( $key, $q->param($key) );
    }

    return "";
}

1;

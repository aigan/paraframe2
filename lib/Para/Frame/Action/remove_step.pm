package Para::Frame::Action::remove_step;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2009 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.010;
use strict;
use warnings;

=head1 NAME

Para::Frame::Action::remove_step - removes a step from the route

=cut

sub handler
{
    my( $req ) = @_;

    my $route = $req->s->route;

    $route->remove_step;

    return "Tar bort ett steg";
}

1;

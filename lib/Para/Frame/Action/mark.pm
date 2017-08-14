package Para::Frame::Action::mark;
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

use Para::Frame::Utils qw( store_params debug );
use Para::Frame::URI;


=head1 NAME

Para::Frame::Action::mark - bookmarks a page for the route

=cut

# See Para::Frame::Route
#

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $route = $req->s->route;

    my @run_in = $q->param('run');
    my @run_out = grep {$_ ne 'mark'} @run_in;
    $q->param('run', @run_out );

    my $uri = Para::Frame::URI->new($req->referer_with_query);
    $uri->query_param('run',[@run_out]);

    $route->bookmark( $uri );

    return "";
}

1;

package Para::Frame::Renderer::Test_AJAX;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2015 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================


use base 'Para::Frame::Renderer::Custom';
use Test::More;
use JSON; # to_json from_json

use Para::Frame::Utils qw( debug );

sub render_output
{
    my( $rend ) = @_;

    my $file = $rend->url_path;
    my $req =  $rend->req;
    my $q = $req->q;
    my $u = $req->user;
    my $params = {};

    foreach my $key ( $q->param )
    {
        $params->{$key} = [];
        foreach my $val ( $q->param($key ) )
        {
            push @{$params->{$key}}, $val;
        }
    }

    my $out = to_json( {
                        path => $file,
                        params => $params,
                        user => $u->{username},
                       } );

    debug 2, "RENDERING:\n$out\n.";

    return \ $out;
}


1;

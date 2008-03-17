#  $Id$  -*-cperl-*-
package Para::Frame::Action::language_set;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2008 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;

use Para::Frame::Utils qw( throw passwd_crypt debug );

=head1 NAME

Para::Frame::Action::user_login - For logging in

=head1 DESCRIPTION

Paraframe language set action

=cut

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $msg;

    # TODO: Check if old eq new

    if( my $lc = $q->param('lang') )
    {
	$req->cookies->add({
			    'lang' => $lc,
			   });
	$req->set_language($lc);
	$msg = "Changed language to $lc";
    }
    else
    {
	$req->cookies->remove('lang');
	$req->set_language($req->env->{HTTP_ACCEPT_LANGUAGE});

	$msg = "Removed the language choice";
    }

    # May have to change page
    $req->reset_response;

    return $msg;
}

1;


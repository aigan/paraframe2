#  $Id$  -*-perl-*-
package Para::Frame::Action::language_set;
#=====================================================================
#
# DESCRIPTION
#   Paraframe language set action
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2006 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;

use Para::Frame::Utils qw( throw passwd_crypt debug );

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;

    if( my $lc = $q->param('lang') )
    {
	$req->cookies->add({
			    'lang' => $lc,
			   });
	return "Ändrade språket till $lc";
    }
    else
    {
	$req->cookies->remove('lang');
	$req->set_language($req->env->{HTTP_ACCEPT_LANGUAGE});
	return "Tog bort språkval";
    }
}

1;


=head1 NAME

Para::Frame::Action::user_login - For logging in

=cut

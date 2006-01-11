#  $Id$  -*-perl-*-
package Para::Frame::Action::user_login;
#=====================================================================
#
# DESCRIPTION
#   Paraframe user login action
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004 Jonas Liljegren.  All Rights Reserved.
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

    # Validation
    #
    my $username = $q->param('username')
	or throw('incomplete', "Namn saknas\n");
    my $password = $q->param('password') || "";
    my $remember = $q->param('remember_login') || 0;

    # Do not repeat failed login in backtrack
    $req->{'no_bookmark_on_failed_login'}=1;

    my @extra = ();
    if( $remember )
    {
	push @extra, -expires => '+10y';
    }

    my $user_class = $Para::Frame::CFG->{'user_class'};
    my $u = $user_class->get( $username );
    $u or throw('validation', "Användaren $username existerar inte");
    
    $user_class->change_current_user( $u );

    my $password_encrypted = passwd_crypt( $password );

    if( $user_class->authenticate_user( $password_encrypted ) )
    {
	$req->cookies->add({
	    'username' => $username,
	    'password' => $password_encrypted,
	},{
	    @extra,
	});

	$q->delete('username');
	$q->delete('password');

	$req->run_hook('user_login', $u);

	return "$username loggar in";
    }

    return "Inloggningen misslyckades\n";
}

1;

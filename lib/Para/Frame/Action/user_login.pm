#  $Id$  -*-cperl-*-
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
#   Copyright (C) 2004-2006 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;

use Para::Frame::Utils qw( throw passwd_crypt debug datadump );

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;

    # Validation
    #
    my $username = join('',$q->param('username'))
	or throw('incomplete', "Namn saknas\n");
    my $password = join('',$q->param('password')) || "";
    my $remember = $q->param('remember_login') || 0;

    $password or throw('incomplete', "Ange lösenord också");


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

    #Also catch exceptions
    my $msg = eval
    {
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

	    debug "Login sucessful";
	    return "$username loggar in";
	}

	debug "Login failed gracefully";
    };
    if( my $err = $@ )
    {
	debug "Got exception during login";
	$u = $user_class->get('guest');
	$user_class->change_current_user( $u );
	die $err; # Since user change may reset $@
    }

    $msg ||= "Inloggningen misslyckades";

    return $msg;
}

1;


=head1 NAME

Para::Frame::Action::user_login - For logging in

=cut

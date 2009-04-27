package Para::Frame::Action::user_login;
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

use Para::Frame::Utils qw( throw passwd_crypt debug datadump );
use Para::Frame::L10N qw( loc );


=head1 NAME

Para::Frame::Action::user_login - For logging in

=cut

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $user_class = $Para::Frame::CFG->{'user_class'};

    $req->run_hook('before_user_login', $user_class);

    # Validation
    #
    my $username = join('',$q->param('username'))
	or throw('incomplete', loc("Name is missing"));
    my $password = join('',$q->param('password')) || "";
    my $remember = $q->param('remember_login') || 0;

    $password or throw('incomplete', loc("Password is missing"));

    # Do not repeat failed login in backtrack
    $req->{'no_bookmark_on_failed_login'}=1;

    # Remember login info in this req for later handling
    $req->{'login_username'} = $username;
    $req->{'login_password'} = $password;

    my @extra = ();
    if( $remember )
    {
	push @extra, -expires => '+10y';
    }

    my $u = $user_class->get( $username,
			      {
			       password => $password,
			      }
			    );
    $u or throw('validation', loc('The user [_1] doesn\'t exist', $username));

    debug "User is $u";

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
	debug "Error: $err";
	$u = $user_class->get('guest');
	$user_class->change_current_user( $u );
	die $err; # Since user change may reset $@
    }

    $msg ||= "Inloggningen misslyckades";

    return $msg;
}

1;

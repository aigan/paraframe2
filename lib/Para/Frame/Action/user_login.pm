package Para::Frame::Action::user_login;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2016 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.010;
use strict;
use warnings;

use Digest::MD5  qw(md5_hex);

use Para::Frame::Utils qw( throw passwd_crypt debug datadump );
use Para::Frame::L10N qw( loc );


=head1 NAME

Para::Frame::Action::user_login - For logging in

If md5_salt is set in config, it encrypts the password with this salt
before passing it on; requiring that the password is checked with the
same md5-encryption.

=cut

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $user_class = $Para::Frame::CFG->{'user_class'};

    $req->run_hook('before_user_login', $user_class);

    # Validation
    #
    my $username = (grep(length($_),$q->param('username')))[0]
      or throw('incomplete', loc("Name is missing"));
    my $password = (grep(length($_),$q->param('password')))[0]
      or throw('incomplete', loc("Password is missing"));
    my $remember = $q->param('remember_login') || 0;

    $password or throw('incomplete', loc("Password is missing"));

    # Do not repeat failed login in backtrack
    $req->{'no_bookmark_on_failed_login'}=1;

    # Remember login info in this req for later handling
    $req->{'login_username'} = $username;
    $req->{'login_password'} = $password;

    my @extra = ();
    if ( $remember )
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

    # DEPRECATED (2016). Use server_salt instead
    #
    # If md5-salt is set, the password is encrypted in db, and double
    # encrypted for cookie
    if ( my $md5_salt = $Para::Frame::CFG->{'md5_salt'} )
    {
        $password = md5_hex($password, $md5_salt);
    }
    else
    {
        $password = $u->password_token( $password );
    }


    # Encrypt password with IP (for cookie)
    my $password_encrypted = passwd_crypt( $password );

    #Also catch exceptions
    my $msg = eval
    {
        if ( $user_class->authenticate_user( $password_encrypted ) )
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
    if ( my $err = $@ )
    {
        debug "Got exception during login";
        debug "Error: $err";
        $u = $user_class->get('guest');
        $user_class->change_current_user( $u );
        die $err;               # Since user change may reset $@
    }

    $msg ||= loc("Login failed");

    return $msg;
}

1;

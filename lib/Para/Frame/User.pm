package Para::Frame::User;
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

=head1 NAME

Para::Frame::User - Represents the user behind the request

=cut

use 5.010;
use strict;
use warnings;

use Carp qw( confess cluck );

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw passwd_crypt debug datadump );
use Para::Frame::L10N qw( loc );

=head1 SYNOPSIS

  package My::User;
  use Para::Frame::Utils qw( throw passwd_crypt );
  use base qw(Para::Frame::User);

  sub verify_password
  {
    my( $u, $password_encrypted ) = @_;

    $password_encrypted ||= '';

    if( $password_encrypted eq passwd_crypt($u->{'passwd'}) )
    {
	return 1;
    }
    else
    {
	return 0;
    }
  }

  sub get
  {
      my( $class, $username ) = @_;

      my $rec;

      if( $username eq 'egon' )
      {
        $rec =
        {
          name => 'Egon Duktig',
          username => 'egon',
          uid      => 123,
          level    => 1,
          passwd   => 'hemlis',
        };
      elsif( $username eq 'guest' )
      {
        $rec =
        {
          name => 'The guest',
          username => 'guest',
          uid      => 0,
          level    => 0,
        };
      }
      else
      {
        return undef;
      }

      return bless $rec, $class;
  }


=head1 DESCRIPTION

This is the base class for the application User class.  The user
object can be accessed as C<$req-E<gt>u> from Perl and C<user> from
templates.

=head1 Methods

=cut


##############################################################################

=head2 identify_user

  $class->identify_user()

  $class->identify_user( $username )

  $class->identify_user( $username, \%args )

C<%args> may include:

  password_encrypted

This will only identify who the client is claiming to
be. Authentication is done by L</authenticate_user>.

C<$username> will default to cookie C<username>.
C<$args-E<gt>{password_encrypted}> will default to cookie C<password>.

Password is used for cases when where may be more than one user with
the same username.

Subclass L</get> to actually looking up and returning the user.

L</identify_user> and L</authenticate_user> is called at the beginning
of each request that does not have a sotred result.

=cut

sub identify_user
{
    my( $this, $username, $args ) = @_;
    my $class = ref($this) || $this;

    my $req = $Para::Frame::REQ;
    my $q = $req->q;
    $username ||= $q->cookie('username') || 'guest';

    $args ||= {};
    $args->{'password_encrypted'} ||= $q->cookie('password') || "";

    debug(3,"identifying $username");
    my $u = $class->get( $username, $args );
    unless( $u )
    {
        if ( $username eq 'guest' )
        {
            die "Couldn't find user guest";
        }

        my $errmsg = $this->user_not_found_msg( $username, $args );
        $req->result->message($errmsg);

        cluck "USER $username NOT FOUND";
        $class->clear_cookies;
        $u = $class->identify_user( 'guest' );
    }

    $class->change_current_user( $u );
    return $u;
}


##############################################################################

=head2 user_not_found_msg

=cut

sub user_not_found_msg
{
    my( $this, $username, $args ) = @_;
    return loc('The user [_1] doesn\'t exist', $username);
}


##############################################################################

=head2 authenticate_user

=cut

sub authenticate_user
{
    my( $this, $password_encrypted ) = @_;
    my $class = ref($this) || $this;

    my $u   = $Para::Frame::U or confess "No user to authenticate";
    my $req = $Para::Frame::REQ;
    my $q   = $req->q;

    $password_encrypted ||= $q->cookie('password') || "";

    my $username = $u->username;

    unless( $username )
    {
        debug "No username for $u->{id} ($u)";
        my $ucl = ref $u;
        debug "  class $ucl";
        no strict "refs";
        foreach my $isa (@{"${ucl}::ISA"})
        {
            debug " - $isa";
        }
        confess "no username";
    }
    debug(3,"authenticating $username");
    debug(3,"  with password $password_encrypted");

    if ( $username eq 'guest' )
    {
        return 1;
    }

    if ( $u->cas_session )
    {
        unless( $u->cas_verified )
        {
            $req->result->message('Session expired');
            $class->logout;
            return undef;
        }
    }
    elsif ( not $u->verify_password( $password_encrypted ) )
    {
        $req->result->exception('validation', "Wrong password for $username");

        $class->logout;
        return undef;
    }

    # could be changed by a reset
    $username = $u->username;

    # Sanitycheck
    unless( $username )
    {
        throw('action', "User object has invalid username ($username)\n");
    }


    warn "# $username\n";

    return 1;
}


##############################################################################

=head2 get

  $this->get( $username )

Returns the user object, or undef if no such user exist.

This method should be reimplemented in a User class that inherits from
this class.

See the example above.

The special user guest should always be recognized and the user object
must always contain the hash fields given in the example.

Do not throw any exceptions in this code.

=cut

sub get                         # Reimplement this method
{
    my( $class, $username ) = @_;

    my $u = bless {}, $class;

    $u->{'name'} = 'Guest';
    $u->{'username'} = 'guest';
    $u->{'uid'} = 0;
    $u->{'level'} = 0;

    return $u;
}


##############################################################################

=head2 verify_password

  $u->verify_password( $encrypted_password )

Returns true or false.

Compare the password as in the example above, using
L<Para::Frame::User/passwd_crypt>. See this function for the
restrictions.

=cut

sub verify_password             # Reimplement this method
{
    my( $u, $password_encrypted ) = @_;

    throw('validation', "Not implemented");
    0;
}


##############################################################################

=head2 cas_session

=cut

sub cas_session
{
    return 0;
}


##############################################################################

=head2 cas_verified

=cut

sub cas_verified
{
    return 0;
}


##############################################################################

=head2 logout

  $u->logout

Logs out the user.

Removes the cookies.

=cut

sub logout
{
    my( $this ) = @_;
    my $class = ref($this) || $this;

    my $req = $Para::Frame::REQ;

    # Set the user of the session to guest
    debug(2,"Logging out user");
    Para::Frame->run_hook($req, 'before_user_logout', $Para::Frame::U)
        unless $Para::Frame::U->level == 0;
    $class->change_current_user( $class->get( 'guest' ) );
    debug(3,"User are now ".$Para::Frame::U->name);

    $class->clear_cookies;
    $req->session->after_user_logout;


    # Do not run hook if we are on guest level
    Para::Frame->run_hook($req, 'after_user_logout')
        unless $Para::Frame::U->level == 0;
}


##############################################################################

=head2 clear_cookies

=cut

sub clear_cookies
{
    my( $class ) = @_;

    my $cookies = $Para::Frame::REQ->cookies;

    $cookies->add({'username' => 'guest'});
    $cookies->remove('password');
}


##############################################################################

=head2 change_current_user

  $u->change_current_user( $new_user )

Sets the user for this request to the object C<$new_user>.

=cut

sub change_current_user
{
    unless( UNIVERSAL::isa $_[1], 'Para::Frame::User' )
    {
        cluck "Tried to set user to $_[1]";
        throw('validation', sprintf "%s is not a valid user", $_[1]->sysdesig );
    }

    $Para::Frame::U = $_[1];
    return $Para::Frame::U unless $Para::Frame::REQ;
    return $Para::Frame::REQ->session->{'user'} = $Para::Frame::U;
}


##############################################################################

=head2 become_temporary_user

  $u->become_temporary_user( $new_user )

Temporarily change the user for this request to the object
C<$new_user>, for some special operation. Remember who the real user
is.  Make sure to switch back then done, and use C<eval{}> to catch
errors and switch back before any exception.

Switch back to the real user with L</revert_from_temporary_user>.

Example:
  $Para::Frame::U->become_temporary_user($root);
  eval
  {
    # do your stuff...
  };
  $Para::Frame::U->revert_from_temporary_user;
  die $@ if $@;

=cut

sub become_temporary_user
{
    $Para::Frame::REQ->{'real_user'} = $Para::Frame::U;
    return $_[0]->change_current_user( $_[1] );
}


##############################################################################

=head2 revert_from_temporary_user

  $u->revert_from_temporary_user

Reverts back from the temporary user to the user before
L</become_temporary_user>.

=cut

sub revert_from_temporary_user
{
    if ( my $ru = delete $Para::Frame::REQ->{'real_user'} )
    {
        return $_[0]->change_current_user( $ru );
    }
    return $Para::Frame::U;
}

##############################################################################

=head2 name

The real name of the user.  Default is 'Guest'.

=cut

sub name     { $_[0]->{'name'} }

##############################################################################

=head2 desig

Conflicts with RB Resource desig...

=cut

#sub desig     { $_[0]->{'name'} }

##############################################################################

=head2 username

A unique handle for the user, following the rules of a unix username.
Default is 'guest'.

=cut

sub username { $_[0]->{'username'} }

##############################################################################

=head2 uid

A unique integer identifier for the user.  Default is 0.

=cut

sub uid      { $_[0]->{'uid'} }

sub id       { $_[0]->{'uid'} }

##############################################################################

=head2 level

The access level for the user.  A user can access everything with a
level less than or equal to her level.  Default is 0.

=cut

sub level    { $_[0]->{'level'} }

##############################################################################

=head2 style

=cut

sub style    { undef }


##############################################################################

# Shortcuts
#
# TODO: Remove the use of these!

sub session { $Para::Frame::REQ->session }
sub route   { $Para::Frame::REQ->session->route }


##############################################################################

=head2 has_root_access

=cut

sub has_root_access
{
    return $_[0]->level > 41 ? 1 : 0;
}

##############################################################################

=head2 has_cm_access

Content management access

=cut

sub has_cm_access
{
    return $_[0]->level > 19 ? 1 : 0;
}

##############################################################################

=head2 has_page_update_access

  $u->has_page_update_access()

  $u->has_page_update_access( $file )

Reimplement this to give update access for a specific page or the
default access for the given user.

C<$file> must be a L<Para::Frame::File> object.

Returns: true or false

The default is false (0).

=cut

sub has_page_update_access
{
    my( $u, $file ) = @_;

    if ( $file )
    {
        unless( UNIVERSAL::isa( $file, 'Para::Frame::File' ) )
        {
            throw('action', "File param not a Para::Frame::File object");
        }
    }

    return 0;
}

##############################################################################

=head2 apply_access_token

=cut

sub apply_access_token
{
    my( $u, $access_token ) = @_;

    my( $username, $info ) = $u->validate_access_token( $access_token );

    $u->identify_user($username); # Will set $s->{user}
    return;

}

##############################################################################

=head2 validate_access_token

=cut

sub validate_access_token
{
    my( $u, $access_token ) = @_;

#    debug "Validating access_token $access_token";
    if( my $record = $Para::Frame::CFG->{'access_tokens'}{$access_token} )
    {
#        debug "  token for user ".$record->{user};
        return( $record->{user} );
    }

    return undef;
}

##############################################################################

=head2 password_token

The representation of a password to use as input for cookie
generation. (before iphash)

Reimplement to introduce secure password storage.

=cut

sub password_token
{
    return $_[1];
}

##############################################################################

1;

=head1 SEE ALSO

L<Para::Frame>

=cut

#  $Id$  -*-perl-*-
package Para::Frame::User;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework User class
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

=head1 NAME

Para::Frame::User - Represents the user behind the request

=cut

use strict;
use Carp qw( confess );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw passwd_crypt debug );

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
          name => 'Gäst',
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

=head2 name

The real name of the user.  Default is 'Gäst'.

=head2 username

A unique handle for the user, following the rules of a unix username.
Default is 'guest'.

=head2 uid

A unique integer identifier for the user.  Default is 0.

=head2 level

The access level for the user.  A user can access everything with a
level less than or equal to her level.  Default is 0.

=cut

#sub new
#{
#    my( $class ) = @_;
#
#    $class->identify_user();
#    $class->authenticate_user();
#}

sub identify_user
{
    my( $this, $username ) = @_;
    my $class = ref($this) || $this;

    my $req = $Para::Frame::REQ;
    my $q = $req->q;
    $username ||= $q->cookie('username') || 'guest';
    debug(3,"identifying $username");
    my $u = $class->get( $username );
    unless( $u )
    {
	if( $username eq 'guest' )
	{
	    die "Couldn't find user guest";
	}

	$req->result->message("Användaren $username existerar inte");
	$class->clear_cookies;
	$u = $class->identify_user( 'guest' );
    }

    $class->change_current_user( $u );
    return $u;
}

sub authenticate_user
{
    my( $this, $password_encrypted ) = @_;
    my $class = ref($this) || $this;

    my $u   = $Para::Frame::U;
    my $req = $Para::Frame::REQ;
    my $q   = $req->q;

    $password_encrypted ||= $q->cookie('password') || "";

    my $username = $u->username;
    debug(3,"authenticating $username");
    debug(3,"  with password $password_encrypted");

    if( $username eq 'guest' )
    {
	return 1;
    }

    unless( $u->verify_password( $password_encrypted ) )
    {
	$req->result->exception('validation', "Fel lösenord för $username");

	$class->logout;

	if( debug )
	{
	    warn sprintf("  next_template was %s\n",
			 $q->param('next_template'))
		if $q->param('next_template');
	    warn sprintf("  destination was %s\n",
			 $q->param('destination'))
		if $q->param('destination');
	}

	my $destination = $q->param('destination') || '';
	unless( $destination eq 'dynamic' )
	{
	    $q->param('next_template', $req->referer);
	    warn sprintf("  Setting next_tempalte to %s\n",
			 $q->param('next_template'));
	}

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

sub verify_user # NOT USED
{
    throw('action', "Not used");
}

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

sub get # Reimplement this method
{
    my( $class, $username ) = @_;

    my $u = bless {}, $class;

    $u->{'name'} = 'Gäst';
    $u->{'username'} = 'guest';
    $u->{'uid'} = 0;
    $u->{'level'} = 0;

    return $u;
}

=head2 verify_password

  $u->verify_password( $encrypted_password )

Returns true or false.

Compare the password as in the example above, using
L<Para::Frame::User/passwd_crypt>. See this function for the
restrictions.

=cut

sub verify_password # Reimplement this method
{
    my( $u, $password_encrypted ) = @_;

    throw('validation', "Not implemented");
    0;
}

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

sub clear_cookies
{
    my( $class ) = @_;

    my $cookies = $Para::Frame::REQ->cookies;

    $cookies->add({'username' => 'guest'});
    $cookies->remove('password');
}

=head2 change_current_user

  $u->change_current_user( $new_user )

Sets the user for this request to the object C<$new_user>.

=cut

sub change_current_user
{
    $Para::Frame::U = $_[1];
    return $Para::Frame::U unless $Para::Frame::REQ;
    return $Para::Frame::REQ->session->{'user'} = $Para::Frame::U;
}

=head2 become_temporary_user

  $u->become_temporary_user( $new_user )

Temporarily change the user for this request to the object
C<$new_user>, for some special operation. Remember who the real user
is.  Make sure to switch back then done, and use C<eval{}> to catch
errors and switch back before any exception.

Switch back to the real user with L</revert_from_temporary_user>.

=cut

sub become_temporary_user
{
    $Para::Frame::REQ->{'real_user'} = $Para::Frame::U;
    return $_[0]->change_current_user( $_[1] );
}

=head2 revert_from_temporary_user

  $u->revert_from_temporary_user

Reverts back from the temporary user to the user before
L</become_temporary_user>.

=cut

sub revert_from_temporary_user
{
    if( my $ru = delete $Para::Frame::REQ->{'real_user'} )
    {
	return $_[0]->change_current_user( $ru );
    }
    return $Para::Frame::U;
}




# Create accessors
#
sub name     { $_[0]->{'name'} }
sub username { $_[0]->{'username'} }
sub uid      { $_[0]->{'uid'} }
sub id       { $_[0]->{'uid'} }
sub level    { $_[0]->{'level'} }
sub style    { undef }

# Shortcuts
#
sub session { $Para::Frame::REQ->session }
sub route   { $Para::Frame::REQ->session->route }

# Default implementation
#
sub has_root_access
{
    return $_[0]->level > 41 ? 1 : 0;
}


1;

=head1 SEE ALSO

L<Para::Frame>

=cut

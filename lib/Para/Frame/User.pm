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
use Time::HiRes qw( time );
use Carp qw( confess );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "  Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw passwd_crypt debug );

=head1 SYNOPSIS

  package My::User;
  use Para::Frame::Utils qw( throw );
  use base qw(Para::Frame::User);

  sub verify_user
  {
      my( $u, $username, $password ) = @_;

      my $uid;       # Numerical Id of user
      my $level;     # Access level of user, 0 = guest access
      my $rela_name; # Full name

      if( $username eq 'egon' )
      {
          if( $password eq 'secret' )
          {
              $uid       =  1;
              $level     = 10;
              $real_name = "Egon Duktig";
          }
          else
          {
	      throw('validation', "Wrong password for $username");
          }
      }
      else
      {
          throw('validation', "User '$username' doesn't exist");
      }

      # Clear out any old data
      $u->clear;

      $u->{'username'} = $username;
      $u->{'name'}     = $real_name;
      $u->{'uid'}      = $uid;
      $u->{'level'}    = $level;

      return 1; # Successful identification
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

sub new
{
    my( $class ) = @_;

    $class->identify_user();
    $class->authenticate_user();
}

sub identify_user
{
    my( $class, $username ) = @_;

    my $req = $Para::Frame::REQ;
    my $q = $req->q;
    $username ||= $q->cookie('username') || 'guest';
    debug(3,"identifying $username");
    my $u = $class->get( $username );
    unless( $u )
    {
	$req->result->message("Användaren $username existerar inte");
	$u = $class->identify_user( 'guest' );
    }

    $class->change_current_user( $u );
    return $u;
}

sub authenticate_user
{
    my( $class, $password_encrypted ) = @_;

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
			 $q->param('next_template'));
	    warn sprintf("  destination was %s\n",
			 $q->param('destination'));
	}

	my $destination = $q->param('destination') || '';
	unless( $destination eq 'dynamic' )
	{
	    $q->param('next_template', $req->referer);
	}
	warn sprintf("  Setting next_tempalte to %s\n",
		     $q->param('next_template'));

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

sub verify_user # Reimplement this method
{
    my( $u, $username, $password ) = @_;

    # Example:
    #
    # throw('validation', "Ingen med namnet ".
    #     "'$username' existerar\n");
    #
    # throw('validation', "Fel lösenord för $username\n");

    throw('validation', "Not implemented");
    0;
}

sub logout
{
    my( $class ) = @_;

    my $req = $Para::Frame::REQ;

    # Set the user of the session to guest
    debug(2,"Logging out user");
    Para::Frame->run_hook($req, 'before_user_logout', $Para::Frame::U)
	unless $Para::Frame::U->level == 0;
    $class->change_current_user( $class->get( 'guest' ) );
    debug(3,"User are now ".$Para::Frame::U->name);

    $req->cookies->add({'username' => 'guest'});
    $req->cookies->remove('password');

    # Do not run hook if we are on guest level
    Para::Frame->run_hook($req, 'after_user_logout')
	unless $Para::Frame::U->level == 0;
}

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

sub change_current_user
{
    $Para::Frame::U = $_[1];
    return $Para::Frame::U unless $Para::Frame::REQ;
    return $Para::Frame::REQ->s->{'user'} = $Para::Frame::U;
}


# Create accessors
#
sub name     { $_[0]->{'name'} }
sub username { $_[0]->{'username'} }
sub uid      { $_[0]->{'uid'} }
sub level    { $_[0]->{'level'} }
sub style    { undef }

# Shortcuts
#
sub session { $Para::Frame::REQ->s }
sub s       { $Para::Frame::REQ->s }
sub route   { $Para::Frame::REQ->s->route }

1;

=head1 SEE ALSO

L<Para::Frame>

=cut

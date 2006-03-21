#  $Id$  -*-perl-*-
package Para::Frame::Session;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Session class
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

Para::Frame::Session - Session handling

=cut

use strict;
use CGI;
use FreezeThaw qw( thaw );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Time qw( now );
use Para::Frame::User;
use Para::Frame::Route;
use Para::Frame::URI;
use Para::Frame::Utils qw( store_params debug );

our $SESSION_COOKIE_NAME = 'paraframe-sid';

=head1 DESCRIPTION

You get this object by L<Para::Frame::Request/session>.

If you subclass this class, set the name of yo0ur class in
L<Para::Frame/session_class>.

=cut

sub new
{
    my( $class, $req ) = @_;

    my( $s, $sid, $active );

    my $now = now();

    # Each user can have more than one session
    # An explicit logout creates a new session

    # Existing session cookie?
    if( my $s_cookie = $req->cookies->hash->{$SESSION_COOKIE_NAME} )
    {
	$sid = $s_cookie->value;

	# Session still alive?
	if( $s = $Para::Frame::SESSION{$sid} )
	{
	    $s->{'latest'} = $now;
	    return $s;
	}

	$active = 0;
    }
    else # Create new session ID if no cookie active
    {
	# REQNUM is actually the previous number, but it will be
	# unique so that doesn't matter
	#
	$sid = time.'-'.$Para::Frame::REQNUM;
	$req->cookies->add({ $SESSION_COOKIE_NAME => $sid });
	$active = 1;
    }

    $s =  bless
    {
	sid            => $sid,
	active         => $active,
	created        => $now,
	latest         => $now,
	user           => undef,
	debug          => $Para::Frame::CFG->{'debug'},
	template_error => '', # Default
        list           => {},
        listid         => 1,
    }, $class;

    # Register s
    $Para::Frame::SESSION{$sid} = $s;

    # Create a route object for the session
    $s->{'route'} = Para::Frame::Route->new();

    $s->init;

    return $s;
}

=head2 init

  $s->init

This is called after the session construction.

Reimplement this mothod if you subclass C<Para::Frame::Session>.

The default method is empty.

=cut

sub init
{
    # Reimplement this
}

sub new_minimal
{
    my( $class ) = @_;

    # Used for background jobs, not bound to a browser client

    my $sid = time.'-'.$Para::Frame::REQNUM;
    my $now = now();

    my $s =  bless
    {
	sid            => $sid,
	active         => 1,
	created        => $now,
	latest         => $now,
	user           => undef,
	debug          => $Para::Frame::CFG->{'debug'},
	template_error => '', # Default
    }, $class;

    # Register s
    $Para::Frame::SESSION{$sid} = $s;

    return $s;
}

sub after_request
{
    my( $s, $req ) = @_;

    # This is the uri of the previous request. Not necessarily the
    # referer of the next request.

    $s->{'referer'} = Para::Frame::URI->new($req->normalized_uri);
    $s->{'referer'}->query_form(store_params());
}

sub register_result_page
{
    my( $s, $uri, $headers, $page_ref ) = @_;
    # URI should only be the path part
    debug "Registred the page result for $uri";
    $s->{'page_result'}{$uri} = [ $headers, $page_ref ];
}

=head2 id

  $s->id

Returns the session id.

=cut

sub id
{
    return $_[0]->{'sid'};
}

=head2 user

  $s->user

Returns the session user object. L<Para::Frame::User> or an object in
your subclass of that.

=cut

sub u
{
    return $_[0]->{'user'};
}

sub user
{
    return $_[0]->{'user'};
}

=head2 referer

  $s->referer

Returns a L<URI> object of the previous page visited in the session.

(A user can have several browser windows opened in the same session.)

=cut

sub referer
{
    return $_[0]->{'referer'};
}

=head2 route

  $part->route

Returns the L<Para::Frame::Route> object.

=cut

sub route
{
    return $_[0]->{'route'};
}

sub debug_data
{
    my( $s ) = @_;

    my $out = "";

    $out .= "Session id: $s->{'sid'}\n";
    $out .= "Session created $s->{'created'}\n";
    $out .= "Debug level is $s->{'debug'}\n";
    my $udesig = $s->u->desig;
    $out .= "User is $udesig\n";
    return $out;
}

=head2 list

  $s->list( $id )

Returns the previously stored L<Para::Frame::List> object number
C<$id>.

=cut

sub list
{
    my( $s, $id ) = @_;

    return undef unless $id;
    debug "Returning cached list $id";

    return $s->{list}{$id};
}

=head2 debug_level

  $s->debug_level

Return the session debug level

=cut

sub debug_level
{
    return $_[0]->{'debug'};
}

=head2 set_debug

  $s->set_debug

Sets and return the session debug level

=cut

sub set_debug
{
    return $Para::Frame::DEBUG = $_[0]->{'debug'} = int($_[1]);
}



=head1 SEE ALSO

L<Para::Frame>

=cut


1;

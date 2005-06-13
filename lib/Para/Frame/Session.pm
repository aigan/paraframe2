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

use strict;
use CGI;
use FreezeThaw qw( thaw );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Time;
use Para::Frame::User;
use Para::Frame::Route;

our $SESSION_COOKIE_NAME = 'paraframe-sid';
our $DEBUG = 1;

sub new
{
    my( $class, $req ) = @_;

    my( $s, $sid, $active );

    # Each user can have more than one session
    # An explicit logout creates a new session

    # Existing session cookie?
    if( my $s_cookie = $req->cookies->hash->{$SESSION_COOKIE_NAME} )
    {
	$sid = $s_cookie->value;

	# Session still alive?
	if( $s = $Para::Frame::SESSION{$sid} )
	{
	    $s->{'latest'} = localtime;
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
	sid => $sid,
	active => $active,
	created => localtime,
	latest  => localtime,
	user    => undef,
    }, $class;

    # Register s
    $Para::Frame::SESSION{$sid} = $s;

    # Create a route object for the session
    $s->{'route'} = Para::Frame::Route->new();

    return $s;
}

sub after_request
{
    my( $s, $req ) = @_;

    # This is the uri of the previous request. Not necessarily the
    # referer of the next request.

    $s->{'referer'} = $req->template_uri;
}

sub register_result_page
{
    my( $s, $uri, $headers, $page ) = @_;
    # URI should only be the path part
    $s->{'page_result'}{$uri} = [ $headers, $page ];
}

sub id
{
    return $_[0]->{'sid'};
}

sub u
{
    return $_[0]->{'user'};
}

sub referer
{
    return $_[0]->{'referer'};
}

sub route
{
    return $_[0]->{'route'};
}

1;

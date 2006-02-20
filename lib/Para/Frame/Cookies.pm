#  $Id$  -*-perl-*-
package Para::Frame::Cookies;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Cookies class
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
use Carp;
use vars qw( $VERSION );
use CGI::Cookie;
use Data::Dumper;

BEGIN
{
    $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug );

sub new
{
    my( $class, $req ) = @_;

    my $cookie_hash = {};
    if( $req->env->{'HTTP_COOKIE'} )
    {
	$cookie_hash = scalar parse CGI::Cookie( $req->env->{'HTTP_COOKIE'} );
    }

    return bless
    {
	req   => $req,
	added => [],
	hash  => $cookie_hash,
    }, $class;
}

sub req    { $_[0]->{'req'} }
sub added  { $_[0]->{'added'} }
sub hash   { $_[0]->{'hash'} }


# Add cookies to the Apache request object
#
sub add_to_header
{
    my( $self ) = @_;

    my $added = $self->added;
    my $req = $self->req;

    foreach my $cookie ( @$added )
    {
	$req->page->add_header( 'Set-Cookie', $cookie->as_string );
    }
}

sub add
{
    my( $self, $settings, $extra ) = @_;

    my $q = $self->req->q;
    my $cookies = $self->added;

    $extra ||= {};
    $extra->{-path} ||= '/';

    foreach my $key ( keys %$settings )
    {
	my $val = $settings->{$key};

	debug(1,"Add cookie $key: $val");

	push @$cookies, $q->cookie( -name  => $key,
				    -value => $val,
				    %$extra,
				    );
    }
}

sub remove
{
    my $self = shift;

    my $q = $self->req->q;
    my $cookies = $self->added;

    foreach my $key ( @_ )
    {
	push @$cookies, $q->cookie( -name  => $key,
				    -value => 'none',
				    -path  => '/',
				    -expires => "-1h",
				    );
    }
}

sub as_html
{
    my( $self ) = @_;

    my $desc = "";

    $desc .= "<ol>\n";

    foreach my $key ( keys %{$self->hash} )
    {
	$desc .= "<li>$key: ".$self->hash->{$key}->value."\n";
    }
    $desc .= "</ol>\n";

    return $desc;
}

1;

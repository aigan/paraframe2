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
#   Copyright (C) 2004-2006 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::Cookies - Represent the cookies to send back to a client

=cut

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

=head1 DESCRIPTION

You get this object by using L<Para::Frame::Request/cookies>.

This object will be used to generate the headers before sending the
page. Changes can be done on any point up unitl the headers are
sent. Since the page is generated before it's sent, you can even
change the cookies from inside a template, but think about doing it in
an action instead, or in your user class.

For B<reading> cookies sent by the client, use the L</hash> method.

=cut

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
	added => [],
	hash  => $cookie_hash,
    }, $class;
}

sub added  { $_[0]->{'added'} }

=head2 hash

  $cookies->hash

Returns a hashref of cookies. (?)

=cut

sub hash   { $_[0]->{'hash'} }

sub add_to_header
{
    my( $self ) = @_;

    my $added = $self->added;

    foreach my $cookie ( @$added )
    {
	$Para::Frame::REQ->page->add_header( 'Set-Cookie', $cookie->as_string );
    }
}

=head2 add

  $cookies->add( \%namevalues, \%extra_params )

  $cookies->add( \%namevalues )

For each name/value pair in C<%namevalues>, create a corresponding
cookie, with the addition of the C<%extra_params>. See L<CGI::Cookie>
for valid params.

Default C<-path> is '/'.

=cut

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

=head2 reomve

  $cookies->remove( @cookie_names )

Removes the named cookies from the client, using HTTP headers.

=cut

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

=head2 as_html

  $cookies->as_html

Returns a html string as an representation of the cookies sen from the
client.

=cut

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


=head1 AUTHOR

Jonas Liljegren E<lt>jonas@paranormal.seE<gt>

=head1 SEE ALSO

L<Para::Frame::Request>, L<CGI::Cookie>

=cut

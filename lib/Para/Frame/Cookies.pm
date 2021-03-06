package Para::Frame::Cookies;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2017 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Para::Frame::Cookies - Represent the cookies to send back to a client

=cut

use 5.012;
use warnings;

use Carp qw( confess );
use CGI::Cookie;
use Scalar::Util qw(weaken);

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump );

=head1 DESCRIPTION

You get this object by using L<Para::Frame::Request/cookies>.

This object will be used to generate the headers before sending the
page. Changes can be done on any point up unitl the headers are
sent. Since the page is generated before it's sent, you can even
change the cookies from inside a template, but think about doing it in
an action instead, or in your user class.

For B<reading> cookies sent by the client, use the L</hash> method.

=cut

##############################################################################

=head2 new

=cut

sub new
{
    my( $class, $req ) = @_;
    ref $req or die "req missing";

    my $cookie_hash = {};
    if( $req->env->{'HTTP_COOKIE'} )
    {
	$cookie_hash = scalar parse CGI::Cookie( $req->env->{'HTTP_COOKIE'} );
    }

    my $cookies = bless
    {
     added => [],
     hash  => $cookie_hash,
     req   => $req,
    }, $class;

    weaken($cookies->{'req'});
    return $cookies;
}

##############################################################################

=head2 req

=cut

sub req    { $_[0]->{'req'} }

##############################################################################

=head2 added

=cut

sub added  { $_[0]->{'added'} }

##############################################################################

=head2 hash

  $cookies->hash

Returns a hashref of cookies. (?)

=cut

sub hash   { $_[0]->{'hash'} }

##############################################################################

=head2 get_val

Get SINGLE or MULTIPLE values depending on  context

=cut

sub get_val
{
    my( $cookies, $key ) = @_;

    foreach my $added ( @{$cookies->{'added'}} )
    {
#	debug "Looking at ".datadump $added;
	if( $added->name eq $key )
	{
	    my $val = $added->value;
#	    debug "Returning from added $key: $val";
	    return $val;
	}
    }

    if( my $target = $cookies->{'hash'}{$key} )
    {
	my $val = $target->value;
#	debug "Returning from added $key: $val";
	return $val;
    }

    return undef;
}

##############################################################################

=head2 add_to_header

=cut

sub add_to_header
{
    my( $cookies ) = @_;

    my $added = $cookies->added;
    my $resp = $cookies->req->response;

    foreach my $cookie ( @$added )
    {
	$resp->add_header( 'Set-Cookie', $cookie->as_string );
    }
}

##############################################################################

=head2 add

  $cookies->add( \%namevalues, \%extra_params )

  $cookies->add( \%namevalues )

For each name/value pair in C<%namevalues>, create a corresponding
cookie, with the addition of the C<%extra_params>. See L<CGI::Cookie>
for valid params.

Default C<-path> is the L<Para::Frame::Site/home>

=cut

sub add
{
    my( $cookies, $settings, $extra ) = @_;

    my $req   = $cookies->req;
    my $q     = $req->q;
    my $added = $cookies->added;

    $extra ||= {};

    $extra->{-path} ||= $req->site->home->url_path_slash;

    foreach my $key ( keys %$settings )
    {
	my $val = $settings->{$key};

	debug(1,"Add cookie $key: $val");

	push @$added, $q->cookie( -name  => $key,
				  -value => $val,
				  %$extra,
				);
    }
}

##############################################################################

=head2 add_by_jar

=cut

sub add_by_jar
{
    my( $cookies ) = shift;

    my %arg;
    @arg{qw(ver key val path domain port path_spec secure expires discard hash)} = @_;

    my $extra = {};

    if( $arg{'secure'} )
    {
	$extra->{'-secure'} = 1;
    }

    if( $arg{'expires'} )
    {
	$extra->{'-expires'} = $arg{'expires'};
    }

    $cookies->add({ $arg{'key'} => $arg{'val'} }, $extra);

    return 1;
}

##############################################################################

=head2 remove

  $cookies->remove( @cookie_names )

  $cookies->remove( \@cookei_names )

  $cookies->remove( \@cookei_names, \%extra_params )

Removes the named cookies from the client, using HTTP headers.

Default C<-path> is the L<Para::Frame::Site/home>

=cut

##############################################################################

=head2 remove

=cut

sub remove
{
    my $cookies = shift;

    my $req = $cookies->req;

    my( $list, $extra );

    if( ref $_[0] )
    {
	$list = $_[0];
	$extra = $_[1];
    }
    else
    {
	$list = [@_];
    }

    $extra ||= {};
    $extra->{-path} ||= $req->site->home->url_path_slash;
    $extra->{-expires} ||= "-1h";


    my $added = $cookies->added;

    foreach my $key ( @$list )
    {
	push @$added, $req->q->cookie( -name  => $key,
						    -value => 'none',
						    %$extra,
						  );
    }
}

##############################################################################

=head2 as_html

  $cookies->as_html

Returns a html string as an representation of the cookies sen from the
client.

=cut

sub as_html
{
    my( $cookies ) = @_;

    my $desc = "";

    $desc .= "<ol>\n";

    foreach my $key ( keys %{$cookies->hash} )
    {
	$desc .= "<li>$key: ".$cookies->hash->{$key}->value."\n";
    }
    $desc .= "</ol>\n";

    return $desc;
}

##############################################################################

1;


=head1 AUTHOR

Jonas Liljegren E<lt>jonas@paranormal.seE<gt>

=head1 SEE ALSO

L<Para::Frame::Request>, L<CGI::Cookie>

=cut

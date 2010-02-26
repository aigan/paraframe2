package Para::Frame::URI;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2010 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Para::Frame::URI - Represent an URI

=cut

use 5.010;
use strict;
use warnings;
use overload ('""'     => sub { $_[0]->{'value'}->as_string },
              '=='     => sub { overload::StrVal($_[0]) CORE::eq
		                overload::StrVal($_[1])
                              },
              fallback => 1,
             );

use URI;
use Carp qw( confess cluck );

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump );
use Para::Frame::Widget;


=head1 DESCRIPTION

Represents an URI. This is a wrapper for L<URI> and L<URI::QueryParam>
that redirects calls to those classes. This class is extendable by
subclasses and it's integrated with L<Para::Frame::File>.

=cut


##############################################################################

=head3 new

Wrapper for L<URI/new>

=cut

sub new
{
    my( $class ) = shift;

    my $uri = URI->new(@_);

    return bless
    {
     value => $uri,
    }, $class;
}


##############################################################################

=head2 as_html

  $uri->as_html( \%attrs )

Supported attrs are:

  label
  ... anything taken by jump

=cut

sub as_html
{
    my( $url, $attrs ) = @_;

    return "" unless $url->{'value'};

    $attrs ||= {};

    my $href = $url->{'value'}->as_string;

#    debug "Getting host for ".datadump($url->{'value'});
    my $label = $attrs->{'label'};
    if( not $label and $url->{'value'}->can('host') )
    {
	$label = $url->{'value'}->host;
    }

    $label ||= $url->{'value'}->as_string;

    return Para::Frame::Widget::jump( $label, $href, $attrs );
}


##############################################################################

=head2 sysdesig

  $uri->sysdesig()

The designation of an object, to be used for node administration or
debugging.

=cut

sub sysdesig
{
    if( my $str = $_[0]->{'value'}->as_string )
    {
	return "URL $str";
    }
    else
    {
	return "URL undef";
    }
}


##############################################################################

=head2 as_string

  $uri->as_string()

See L<URI/as_string>

=cut

sub as_string
{
    return $_[0]->{'value'}->as_string;
}


##############################################################################

=head2 eq

  $uri->eq($uri2)

See L<URI/as_string>

=cut

sub eq
{
    my($self, $other) = @_;
    my( $class ) = ref $self;
    unless( UNIVERSAL::isa $class, "Para::Frame::URI" )
    {
	$class = ref $other;
    }

    # taken from URI::eq

    $self  = $class->new($self, $other) unless ref $self;
    $other = $class->new($other, $self) unless ref $other;

    return( (ref($self) CORE::eq ref($other)) and
	    ( $self->canonical->as_string CORE::eq
	      $other->canonical->as_string ) );
}


##############################################################################

=head2 desig

  $uri->desig()

The designation of an object, to be used for node administration or
debugging.

=cut

sub desig
{
    return $_[0]->{value}->as_string;
}


##############################################################################

=head3 new_abs

See L<URI/new_abs>

=cut

sub new_abs
{
    my( $class ) = shift;

    my $uri = URI->new_abs(@_);

    return bless
    {
     value => $uri,
    }, $class;
}


##############################################################################

=head3 clone

See L<URI/clone>

=cut

sub clone
{
    my $uri = $_[0]->{'value'}->clone;
    my $class = ref $_[0];

    return bless
    {
     value => $uri,
    }, $class;
}


##############################################################################

=head3 getset

Used by most get/set wrapper methods

=cut

sub getset
{
    my( $u, $method ) = (shift, shift);
    if( my $uri = $u->{'value'} )
    {
	return $uri->$method(@_);
    }

    return "";
}


##############################################################################

=head3 scheme

See L<URI/scheme>

=cut

sub scheme
{
    return shift->getset('scheme',@_);
}


##############################################################################

=head3 opaque

See L<URI/opaque>

=cut

sub opaque
{
    return shift->getset('opaque',@_);
}


##############################################################################

=head3 path

See L<URI/path>

=cut

sub path
{
    return shift->getset('path',@_);
}


##############################################################################

=head3 fragment

See L<URI/fragment>

=cut

sub fragment
{
    return shift->getset('fragment',@_);
}


##############################################################################

=head3 canonical

See L<URI/canonical>

=cut

sub canonical
{
    my $val = $_[0]->{'value'};
    my $uri = $val->canonical;

    if( $uri->as_string CORE::eq $val->as_string )
    {
	return $_[0];
    }

    my $class = ref $_[0];
    return bless
    {
     value => $uri,
    }, $class;
}


##############################################################################

=head3 abs

See L<URI/abs>

=cut

sub abs
{
    my $uri = $_[0]->{'value'}->abs($_[1]);

    if( $_[0]->eq( $uri ) )
    {
	return $_[0];
    }

    my $class = ref $_[0];
    return bless
    {
     value => $uri,
    }, $class;
}


##############################################################################

=head3 rel

See L<URI/rel>

=cut

sub rel
{
    my $uri = $_[0]->{'value'}->rel($_[1]);

    if( $_[0]->eq( $uri ) )
    {
	return $_[0];
    }

    my $class = ref $_[0];
    return bless
    {
     value => $uri,
    }, $class;
}


##############################################################################

=head3 authority

See L<URI/authority>

=cut

sub authority
{
    return shift->getset('authority',@_);
}


##############################################################################

=head3 path_query

See L<URI/path_query>

=cut

sub path_query
{
    return shift->getset('path_query',@_);
}


##############################################################################

=head3 path_segments

See L<URI/path_segments>

=cut

sub path_segments
{
    return shift->getset('path_segments',@_);
}


##############################################################################

=head3 query

See L<URI/query>

=cut

sub query
{
    return shift->getset('query',@_);
}


##############################################################################

=head3 query_form

See L<URI/query_form>

=cut

sub query_form
{
    return shift->getset('query_form',@_);
}


##############################################################################

=head3 query_keywords

See L<URI/query_keywords>

=cut

sub query_keywords
{
    return shift->getset('query_keywords',@_);
}


##############################################################################

=head3 userinfo

See L<URI/userinfo>

=cut

sub userinfo
{
    return shift->getset('userinfo',@_);
}


##############################################################################

=head3 host

See L<URI/host>

=cut

sub host
{
    return shift->getset('host',@_);
}


##############################################################################

=head3 port

See L<URI/port>

=cut

sub port
{
    return shift->getset('port',@_);
}


##############################################################################

=head3 host_port

See L<URI/host_port>

=cut

sub host_port
{
    return shift->getset('host_port',@_);
}


##############################################################################

=head3 default_port

See L<URI/default_port>

=cut

sub default_port
{
    return $_[0]->{'value'}->default_port;
}


##############################################################################

=head3 getset_query

Used by query get/set wrapper methods

=cut

sub getset_query
{
    my( $u, $method ) = (shift, shift);
    if( my $uri = $u->{'value'} )
    {
	return $uri->$method(@_);
    }

    return "";
}


##############################################################################

=head3 query_param

See L<URI/query_param>

=cut

sub query_param
{
    return shift->getset_query('query_param',@_);
}


##############################################################################

=head3 query_param_append

See L<URI/query_param_append>

=cut

sub query_param_append
{
    return shift->getset_query('query_param_append',@_);
}


##############################################################################

=head3 query_param_delete

See L<URI/query_param_delete>

=cut

sub query_param_delete
{
    return shift->getset('query_param_delete',@_);
}


##############################################################################

=head3 query_form_hash

See L<URI/query_form_hash>

=cut

sub query_form_hash
{
    return shift->getset('query_form_hash',@_);
}


##############################################################################

=head3 retrieve

  $uri->retrieve()

Does a GET request by L<LWP::UserAgent>.

Makes sure that the scheme module is loaded. (Since the object may
have been created in another process.)


=cut

sub retrieve
{
    my( $uri ) = @_;

#    debug"https isa: ".datadump(@URI::https::ISA);
#    debug "https class: $INC{'URI/https.pm'}";

#    debug "Retrieve $uri";

    my $ua = LWP::UserAgent->new;
    my $lwpreq = HTTP::Request->new(GET => $uri->{'value'});

    my $res = $ua->request($lwpreq);
    delete $res->{'handlers'}; # Can't transfer code refs

#    debug "Returning $res";

    return $res;
}


##############################################################################

=head2 jump

  $url->jump( $label, \%attrs )

=cut

sub jump
{
    my( $url, $label, $attrs ) = @_;

    return Para::Frame::Widget::jump($label, $url, $attrs);
}


##############################################################################

#use vars qw($AUTOLOAD);
#sub AUTOLOAD
#{
#    my $method = $AUTOLOAD;
#    $method =~ s/.*:://;
#    return if $method =~ /DESTROY$/;
#    my $node = shift;
#    my $class = ref($node);
#
#    confess "Called $node->$method(@_) for ".datadump($node);
#}


1;


=head1 AUTHOR

Jonas Liljegren E<lt>jonas@paranormal.seE<gt>

=head1 SEE ALSO

L<Para::Frame>, L<URI>, L<URI::QueryParam>, L<Para::Frame::File>

=cut

#  $Id$  -*-perl-*-
package Para::Frame::Request::Ctype;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework request response conetent type class
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

Para::Frame::Request::Ctype - The request response content type

=cut

use strict;
use Carp qw( cluck );
use Scalar::Util qw(weaken);

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug );

=head1 DESCRIPTION

You get this object by using L<Para::Frame::Site::Page/ctype>.

=cut

sub new
{
    my( $class, $req ) = @_;
    ref $req or die "req missing";

    my $ctype =  bless
    {
     ctype   => undef,
     charset => undef,
     changed => 0,
     req     => $req,
    }, $class;
    weaken( $ctype->{'req'} );

    return $ctype;
}

sub req    { $_[0]->{'req'} }

=head2 set

  $ctype->set( $string )

Sets the content type to the given string. The string should be
formatted as in a HTTP header. It can include several extra
parameters.

The only supported extra parameter is C<charset>, that is set using
L</set_charset>.

The actual header isn't written until after the response page has been
generated.

Example:

  $ctype->set("text/plain; charset=UTF-8")

=cut

sub set
{
    my( $ctype, $string ) = @_;

    $string =~ s/;\s+(.*?)\s*$//;
    if( my $params = $1 )
    {
	foreach my $param (split /\s*;\s*/, $params )
	{
	    if( $param =~ /^(.*?)\s*=\s*(.*)/ )
	    {
		my $key = lc $1;
		my $val = $2;

		if( $key eq 'charset' )
		{
		    $ctype->set_charset( $val );
		}
		else
		{
		    warn "  Ctype param $key not implemented";
		}
	    }
	}
    }

    debug(3,"Setting ctype to $string");

    if( defined $ctype->{'ctype'} )
    {
	if( $ctype->{'ctype'} ne $string )
	{
	    $ctype->{'ctype'} = $string;
	    $ctype->{'changed'} ++;
	}
    }
    else
    {
	# First change is regarded as the default, already synced
	$ctype->{'ctype'} = $string;
    }

    return $ctype;
}

=head2 set_charset

  $ctype->set_charset( $charset )

Sets the charset of the content type.

There is no validation of the sting given.

=cut

sub set_charset
{
    my( $ctype, $charset ) = @_;

    if( $ctype->{'charset'}||'' ne $charset )
    {
	$ctype->{'charset'} = $charset;
	warn "  Setting charset to $charset\n";
	$ctype->{'changed'} ++ if $ctype->{'ctype'};
    }
}

=head2 as_string

  $ctype->as_string

Returns a string representation of this object, suitible to be used in
the HTTP header.

=cut

sub as_string
{
    my( $ctype ) = @_;

    my $media = "";
    if( $ctype->{'charset'} )
    {
	$media = sprintf "; charset=%s", $ctype->{'charset'};
    }

    return $ctype->{'ctype'} . $media;
}

sub commit
{
    my( $ctype ) = @_;

    # Set default
    #
    unless( $ctype->{'charset'} )
    {
	$ctype->{'charset'} = "iso-8859-1";
	$ctype->{'changed'} ++;
    }

    if( $ctype->{'changed'} )
    {
	my $string = $ctype->as_string;
	debug(3,"Setting ctype string to $string");
	$ctype->req->send_code( 'AR-PUT', 'content_type', $string);
	$ctype->{'changed'} = 0;
    }
    return 1;
}

1;

=head1 AUTHOR

Jonas Liljegren E<lt>jonas@paranormal.seE<gt>

=head1 SEE ALSO

L<Para::Frame::Site::Page>

=cut

#  $Id$  -*-cperl-*-
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
use Carp qw( cluck confess longmess );
use Scalar::Util qw(weaken);

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump );

=head1 DESCRIPTION

You get this object by using L<Para::Frame::Request::Response/ctype>.

=cut

#######################################################################

=head2 new

L<Para::Frame::Client> will mostly default to C<text/html> and
C<UTF-8>.

=cut

sub new
{
    my( $class, $req ) = @_;
    ref $req or die "req missing";

    my $ctype =  bless
    {
     changed => 0,
    }, $class;
    weaken( $ctype->{'req'} );

    if( my $ctype_string = $req->original_content_type_string )
    {
	$ctype->set( $ctype_string );
    }
    else
    {
	$ctype->{'changed'} ++;
    }

    return $ctype;
}

#######################################################################

=head2 set

  $ctype->set( $string )

Sets the content type to the given string. The string should be
formatted as in a HTTP header. It can include several extra
parameters.

The only supported extra parameter is C<charset>, that is set using
L</set_charset>.

The actual header isn't written until after the response page has been
generated.

Previous parameters will be removed.

Example:

  $ctype->set("text/plain; charset=UTF-8")

=cut

sub set
{
    my( $ctype, $string ) = @_;

#    debug "Ctype set with $string";

    my %param;


    $string =~ s/;\s+(.*?)\s*$//;
    if( my $params = $1 )
    {
	foreach my $param (split /\s*;\s*/, $params )
	{
	    if( $param =~ /^(.*?)\s*=\s*(.*)/ )
	    {
		my $key = lc $1;
		my $val = $2;

		$param{ $key } = $val;
	    }
	}
    }


    # Go through ALL supported keys (that's just one)

    $ctype->set_charset(  delete $param{'charset'} );


    foreach my $key ( keys %param )
    {
	debug "  Ctype param $key not implemented";
    }



    $ctype->set_type( $string );

#    debug "Ctype $ctype set to ".$ctype->as_string;
    return $ctype;
}


#######################################################################

=head2 set_type

  $ctype->set_type( $type )

=cut

sub set_type
{
    my( $ctype, $type ) = @_;

    unless( $type =~ /^[a-z]+\/[a-z\-\+\.0-9]+$/ )
    {
	confess "Malformed content-type $type";
    }

    if( defined $ctype->{'ctype'} )
    {
	if( $ctype->{'ctype'} ne $type )
	{
	    $ctype->{'ctype'} = $type;
	    $ctype->{'changed'} ++;
	}
    }
    else
    {
	# First change is regarded as the default, already synced
	$ctype->{'ctype'} = $type;
    }

}


#######################################################################

=head2 set_charset

  $ctype->set_charset( $charset )

Sets the charset of the content type.

There is no validation of the sting given.

=cut

sub set_charset
{
    my( $ctype, $charset ) = @_;

    if( defined $ctype->{'charset'} )
    {
	if( ($ctype->{'charset'}||'') ne ($charset||'') )
	{
#	    debug longmess "CHECKME";
	    $ctype->{'charset'} = $charset;
	    $ctype->{'changed'} ++;
	}
    }
    else
    {
	# First change is regarded as the default, already synced
	$ctype->{'charset'} = $charset;
    }

#    debug "Charset set to ".($charset||'<undef>');
}


#######################################################################

=head2 charset

  $ctype->charset()

The internal working will always be in UTF8. This controls how text
are sent to the client.

Returns: the current charset

=cut

sub charset
{
    my( $ctype ) = @_;

#    my $charset = $ctype->{'charset'};
#    debug "Returning charset ($ctype) ".($charset || "''");
    return $ctype->{'charset'} || '';
}


#######################################################################

=head2 type

  $ctype->type()

Returns: the current Content-Type

=cut

sub type
{
    my( $ctype ) = @_;

    return $ctype->{'ctype'};
}


#######################################################################

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

    confess "No ctype: ".datadump($ctype,2) unless $ctype->{'ctype'};

    return $ctype->{'ctype'} . $media;
}

#######################################################################

=head2 is

  $ctype->is( $ctype )

=cut

sub is
{
    my( $ctype, $str ) = @_;

    confess() unless( $str );

    if( ($ctype->{'ctype'}||'') eq $str )
    {
	return 1;
    }
    else
    {
	return 0;
    }
}

#######################################################################

=head2 is_defined

=cut

sub is_defined
{
    return $_[0]->{'ctype'} ? 1 : 0;
}

#######################################################################

=head2 commit

=cut

sub commit
{
    my( $ctype ) = @_;

    if( $ctype->is('httpd/unix-directory') )
    {
	$ctype->set('text/html');
    }

    if( $ctype->{'changed'} )
    {
	my $string = $ctype->as_string;
	debug(3,"Setting ctype string to $string");
	$Para::Frame::REQ->send_code( 'AR-PUT', 'content_type', $string);
	$ctype->{'changed'} = 0;
    }

#    debug "Ctype comitted";
    return 1;
}

#######################################################################

1;

=head1 AUTHOR

Jonas Liljegren E<lt>jonas@paranormal.seE<gt>

=head1 SEE ALSO

L<Para::Frame::Request::Response>

=cut

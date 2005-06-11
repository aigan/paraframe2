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
#   Copyright (C) 2004 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;
use Carp qw( cluck );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;

sub new
{
    my( $class, $string ) = @_;

    my $ctype =  bless
    {
	ctype   => undef,
	charset => undef,
	changed => 0,
    }, $class;

    if( $string )
    {
	$ctype->set( $string );
    }

    return $ctype;
}

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

    warn "  Setting ctype to $string\n";

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

sub set_charset
{
    my( $ctype, $charset ) = @_;

    if( $ctype->{'charset'} ne $charset )
    {
	$ctype->{'charset'} = $charset;
	warn "  Setting charset to $charset\n";
	$ctype->{'changed'} ++ if $ctype->{'ctype'};
    }
}

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
	warn "  Setting ctype string to $string\n";
	$Para::Frame::REQ->send_code( 'AR-PUT', 'content_type', $string);
	$ctype->{'changed'} = 0;
    }
    return 1;
}

1;

package Para::Frame::Template::Stash::CheckUTF8;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2009 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================


use 5.010;
use strict;
use warnings;
use utf8;

use Template::Config;
use base ( $Template::Config::STASH );

use Carp qw( confess );
use Encode;

use Para::Frame::Utils qw( debug datadump );


sub get {
    my $self = shift;
    my $result = $self->SUPER::get(@_);
    return $result if ref $result;

    if( utf8::is_utf8($result) )
    {
	if( utf8::valid($result) )
	{
	    if( $result =~ /Ã.(.{30})/ )
	    {
		warn "Double-encoded as UTF8: $1\n";
	    }

#	    warn "Got valid utf8\n";
#
#	    if( $result =~ /(V.+?lkommen|k.+?rningen)/ )
#	    {
#		my $str = $1;
#		my $len1 = length($str);
#		my $len2 = bytes::length($str);
#		warn "  >>$str ($len2/$len1)\n";
#	    }
	}
	else
	{
	    warn "Got INVALID utf8\n";
	}
    }
    else
    {
	if( $result =~ /Ã.(.{0,30})/ )
	{
#	    debug datadump $self;
	    warn "Should have been marked as UTF8: $1\n";
	    Encode::_utf8_on($result);
	}
#	warn "NOT Got utf8\n";
    }


#    Encode::_utf8_on($result) unless Encode::is_utf8($result);
#    unless( utf8::valid($result) )
#      {
#	use Carp;
#	Carp::confess( "Not valid UTF8: 'result'");
#      }
    return $result;
}

1;

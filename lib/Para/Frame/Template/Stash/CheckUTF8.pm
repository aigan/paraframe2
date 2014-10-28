package Para::Frame::Template::Stash::CheckUTF8;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2014 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================


use 5.010;
use strict;
use warnings;
use utf8;

use Template::Config;
use base ( $Template::Config::STASH );

use Carp qw( confess );
use Encode;

use Para::Frame::Utils qw( debug datadump );


sub get
{
    my $self = shift;
    my $result = $self->SUPER::get(@_);
    return $result if ref $result;

    if( utf8::is_utf8($result) )
    {
	    if( $result =~ /Ã.(.{30})/ )
	    {
            warn "Double-encoded as UTF8: $1\n";
	    }
    }
    else
    {
        if( $result =~ /Ã.(.{0,30})/ )
        {
            warn "Should have been marked as UTF8: $1\n";
            Encode::_utf8_on($result);
        }
    }
    return $result;
}

1;

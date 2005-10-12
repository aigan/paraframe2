#  $Id$  -*-perl-*-
package Para::Frame::Change;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework DB Change class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2005 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug );

sub new
{
    my( $class ) = @_;

    my $change = bless {}, $class;

    return $change->reset;
}

sub reset
{
    my( $change ) = @_;

    foreach my $key ( keys %$change )
    {
	delete $change->{$key};
    }

    $change->{'errors'} = 0;
    $change->{'errmsg'} = "";
    $change->{'changes'} = 0;
    $change->{'message'} = "";

    return $change;
}

sub success
{
    my( $change, $msg ) = @_;
    $msg =~ s/\n?$/\n/; # Add if missing
    $change->{'changes'} ++;
    $change->{'message'} .=  $msg;
    return 1;
}

sub note
{
    my( $change, $msg ) = @_;
    $msg =~ s/\n?$/\n/; # Add if missing
    $change->{'message'} .=  $msg;
    debug "Adding note: $msg";
    return 1;
}

sub fail
{
    my( $change, $msg ) = @_;
    $msg =~ s/\n?$/\n/; # Add if missing
    $change->{'errors'} ++;
    $change->{'errmsg'} .=  $msg;
    return undef;
}

sub changes
{
    return $_[0]->{'changes'};
}

sub errors
{
    return $_[0]->{'errors'};
}

sub message
{
    return $_[0]->{'message'};
}

sub errmsg
{
    return $_[0]->{'errmsg'};
}

sub report
{
    my( $change, $errtype ) = @_;

    $errtype ||= 'validation';

    if( length( $change->{'message'} ) )
    {
	$Para::Frame::REQ->result->message( $change->{'message'} );
    }

    if( $change->{'errors'} )
    {
	throw($errtype, $change->{'errmsg'} );
    }

    $change->reset;
    return "";
}

1;

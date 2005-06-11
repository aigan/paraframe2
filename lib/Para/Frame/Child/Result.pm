#  $Id$  -*-perl-*-
package Para::Frame::Child::Result;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Child process result class
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

=head1 NAME

Para::Frame::Child::Result - Representing a child process result

=cut

use strict;
use vars qw( $VERSION );
use FreezeThaw qw( safeFreeze );
use Data::Dumper;

BEGIN
{
    $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;

use Para::Frame::Request;

sub new
{
    my( $class ) = @_;

    my $result = bless
    {
	message   => [],
	exception => [],
	on_return => [],
	pid       => undef,
	status    => undef,
    }, $class;

    return $result;
}

sub message
{
    my( $result, $message ) = @_;

    if( defined $message )
    {
	push @{$result->{'message'}}, $message;
    }
    return wantarray ? @{$result->{'message'}} : $result->{'message'}[-1];
}

sub return
{
    my( $result, $message ) = @_;

    warn "  Returning child result for $Para::Frame::REQ->{reqnum}\n";

    $result->message( $message ) if $message;
    my $data = safeFreeze $result;
    print $data;
    exit;  # don't forget this
}

sub exception
{
    my( $result, $exception ) = @_;

    if( defined $exception )
    {
	push @{$result->{'exception'}}, $exception;
    }

#    warn "child result content after exception: ".Dumper($result);

    return wantarray ? @{$result->{'exception'}} : $result->{'exception'}[0];
}

sub on_return
{
    my( $result, $coderef, @args ) = @_;

    if( $coderef )
    {
	if( ref $coderef )
	{
	    die "coderef should be the name of the function";
	}

	if( $coderef =~ /::/ )
	{
	    die "We do not allow you to set the package";
	}

	my($package, $filename, $line) = caller;

	$coderef = $package . '::' . $coderef;

	$result->{'on_return'} = [$coderef, @args];
    }

    return wantarray ? @{$result->{'on_return'}} : $result->{'on_return'};
}

sub pid
{
    my( $result, $pid ) = @_;

    if( defined $pid )
    {
	$result->{'pid'} = $pid;
    }
    return $result->{'pid'};
}

sub status
{
    my( $result, $status ) = @_;

    if( defined $status )
    {
	$result->{'status'} = $status;
    }

    return $result->{'status'};
}

sub in_child
{
    return 1;
}

sub in_parent
{
    return 0;
}

1;

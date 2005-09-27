#  $Id$  -*-perl-*-
package Para::Frame::Child;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Child process class
#
# We are in the PARENT, looking at the child result
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

Para::Frame::Child - Representing a child process

=cut

use strict;
use vars qw( $VERSION );
use FreezeThaw qw( thaw );
use File::Slurp;
use Data::Dumper;

BEGIN
{
    $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;

use Para::Frame::Utils qw( debug );
use Para::Frame::Request;
use Para::Frame::Child::Result;

sub register
{
    my( $class, $req, $pid, $fh ) = @_;

    my $child = bless
    {
	req      => $req,
	pid      => $pid,
	fh       => $fh,
	status   => undef,
	data     => "",
	result   => undef,
	done     => undef,
    }, $class;

    $req->{'childs'} ++;
    $Para::Frame::CHILD{ $pid } = $child;

    debug(0,"Registerd child $pid");

    return $child;
}

sub deregister
{
    my( $child, $status, $length ) = @_;

    $child->{'done'} = 1; # Taken care of now
    $child->status( $status ) if defined $status;
    my $req = $child->req;

    return if $req->{'cancel'};

    if( $req->in_yield )
    {
	# Used yield. Let main_loop return control to the request

	my $old_req = $Para::Frame::REQ;
	Para::Frame::switch_req( $req );
	eval
	{
	    $child->get_results($length);
	} or do
	{
	    $req->result->exception;
	};
	Para::Frame::switch_req( $old_req ) if $old_req;
    }
    else
    {
	# Using stacked jobs

	# The add_job method is called wihtout switching to the
	# request. Things are set up for the job to be done later, in
	# order and in context.

	$req->add_job('get_child_result', $child, $length);
    }

    $req->{'childs'} --;

    if( $req->{'childs'} <= 0 )
    {
	# Only if set from after_jobs().
	# If we got here AFTER after_jobs, add it
	#
	my $on_last_child_done = $req->{'on_last_child_done'} || 0;
	if( $on_last_child_done eq "after_jobs" )
	{
	    $req->add_job('after_jobs');

	    # Reset. Other forks may be done later
	    $req->{'on_last_child_done'} = 0;
	}
    }

}

sub yield
{
    my( $child ) = @_;

    # Do other things until we get the result from the child
    # Returns the child result obj

    # The reqnum param is just for getting it in backtrace

    my $req = $child->req;
    $req->{'in_yield'} ++;
    Para::Frame::main_loop( $child, undef, $req->{'reqnum'} );
    $req->{'in_yield'} --;
    
    Para::Frame::switch_req( $req );
    return $child->{'result'};
}

sub get_results
{
    my( $child, $length ) = @_;

    # If not all read
    unless( $length )
    {
	my $fh = $child->{'fh'};

	# Some data may already be here, since IO may get stuck otherwise
	#
	$child->{'data'} .= read_file( $fh,
				       'binmode'=>1,
				       ); # Undocumented flag
	close($fh); # Should already be closed then kid exited
    }

    chomp $child->{'data'}; # Remove last \n
    my $tlength = length $child->{'data'};
    if( debug )
    {
	debug(2,"Got $tlength bytes of data");
    }

    unless( $child->{'data'} )
    {
	my $pid = $child->pid;
	my $status = $child->status;
	die "Child $pid didn't return the result (status $status)\n";
    }

    unless( $length )
    {
	$child->{'data'} =~ /^(\d{1,5})\0/;
	$length = $1;
    }
    # Length of prefix
    my $plength = length( $length ) + 1;
    
#    debug "Data length is $length bytes";


#    warn "  got data: $data\n";
    my( $result ) = thaw( substr $child->{'data'}, $plength );
#    warn "  result: $result\n"; ### DEBUG
#    warn Dumper $result; ### DEBUG
    $child->{'result'} = $result;


    delete $child->{'data'}; # We are finished with the raw data

    if( $@ = $result->exception )
    {
	die $@;
    }

    # Transfer some info about the child
    #
    $result->pid( $child->{'pid'} );
    $result->status( $child->{'status'} );

    if( my( $coderef, @args ) = $result->on_return )
    {
#	warn "coderef is '$coderef'\n";
	no strict 'refs';
	$result->message( &{$coderef}( $result, @args ) );
    }

    return $result;
}

sub req
{
    return $_[0]->{'req'};
}

sub pid
{
    return $_[0]->{'pid'};
}

sub status
{
    my( $child, $status ) = @_;

    if( defined $status )
    {
	$child->{'status'} = $status;
    }

    return $child->{'status'};
}

sub result
{
    return $_[0]->{'result'};
}

sub in_child
{
    return 0;
}

sub in_parent
{
    return 1;
}

sub failed
{
    my( $child ) = @_;

    if( $child->result->exception )
    {
	return 1;
    }
    else
    {
	return 0;
    }
}

sub succeeded
{
    my( $child ) = @_;

    if( $child->result->exception )
    {
	return 0;
    }
    else
    {
	return 1;
    }
}

1;

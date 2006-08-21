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
#   Copyright (C) 2004-2006 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::Child - Representing a child process from the PARENTs view

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

use Para::Frame::Utils qw( debug throw );
use Para::Frame::Request;
use Para::Frame::Child::Result;

=head1 DESCRIPTION

Create a fork using L<Para::Frame::Request/create_fork>.

This is the object that the PARENT gets, that is used for recieving
the result from the CHILD.

See L<Para::Frame::Request/create_fork> for examples.

Large results may take considerable time to reconstruct by
L<FreezeThaw/thaw>.

Then the child is done, it returns the L<Para::Frame::Child::Result>
object. If the retrieval of the data succeed, it check for exceptions
in the object added by L<Para::Frame::Child::Result/exception>. If
there are any exceptions, the first of them is given to
L<Para::Frame::Result/exception>. If no exceptins was found, all the
L<Para::Frame::Child::Result/on_return> are run.



=cut

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

    return if $req->cancelled;

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

=head2 yield

  $fork->yield

Do other things until we get the result from the child.

Returns the L<Para::Frame::Child::Result> object.

Using L<Para::Frame::Child::result/on_return> are prefered over
L</yield>.

=cut

sub yield
{
    my( $child ) = @_;


    # The reqnum param is just for getting it in backtrace

    my $req = $child->req;
    $req->{'in_yield'} ++;
    Para::Frame::main_loop( $child, undef, $req->{'reqnum'} );
    $req->{'in_yield'} --;

    Para::Frame::switch_req( $req );

    if( $req->{'cancel'} )
    {
	throw('cancel', "request cancelled");
    }

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

    debug 2, "Data length is $length bytes";


#    warn "  got data: $data\n";
    my( $result ) = thaw( substr $child->{'data'}, $plength );
#    warn "  result: $result\n"; ### DEBUG
#    warn Dumper $result; ### DEBUG
    $child->{'result'} = $result;
    debug 2, "Data result stored";


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

=head2 req

  $fork->req

Returns the request coupled to the fork.

=cut

sub req
{
    return $_[0]->{'req'};
}

=head2

  $fork->pid

Returns the CHILD process id number.

=cut

sub pid
{
    return $_[0]->{'pid'};
}

=head2 status

  $fork->status

Returns the exit status of the CHILD process.

=cut

sub status
{
    my( $child, $status ) = @_;

    if( defined $status )
    {
	$child->{'status'} = $status;
    }

    return $child->{'status'};
}

=head2 result

  $fork->result

Returns the L<Para::Frame::Child::Result> object, after the child is
done.

=cut

sub result
{
    return $_[0]->{'result'};
}

=head2 in_child

  $fork->in_child

Returns false.

=cut

sub in_child
{
    return 0;
}

=head2 in_parent

  $fork->in_parent

Returns true.

=cut

sub in_parent
{
    return 1;
}

=head2 failed

  $fork->failed

Returns true if the child registred an exception.

=cut

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

=head2 succeeded

  $fork->succeeded

Rerurns true if the child didn't register an exception.

=cut

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


=head1 AUTHOR

Jonas Liljegren E<lt>jonas@paranormal.seE<gt>

=head1 SEE ALSO

L<Para::Frame::Request>, L<Para::Frame::Child::Result>

=cut

package Para::Frame::Child::Result;
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

=head1 NAME

Para::Frame::Child::Result - Representing a child process result from CHILDs view

=cut

use 5.010;
use strict;
use warnings;

use Storable qw( freeze);
use Digest::MD5 qw( md5_base64 );

use Para::Frame::Reload;

use Para::Frame::Utils qw( debug datadump );
use Para::Frame::Request;

=head1 DESCRIPTION

Create a fork using L<Para::Frame::Request/create_fork>.

This is the object that the CHILD gets, that is used to send the
result back to the parent.

See L<Para::Frame::Request/create_fork> for examples.

After the CHILD fork is done, you can get this object from the PARENT
by L<Para::Frame::Child/result>. The same methods works both in the
CHILD and the PARENT, but there is no point modifying the object after
CHILD is done.

For example, you may call the object C<$fork> while in the CHILD and
C<$result> while in PARENT.

All parts of the object must survive L<Storable>.

=cut


##############################################################################

=head2 new

=cut

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


##############################################################################

=head2 reset

=cut

sub reset
{
    my( $result ) = @_;

    foreach my $key ( keys %$result )
    {
	delete $result->{$key};
    }

    $result->{'message'} = [];
    $result->{'exception'} = [];
    $result->{'on_return'} = [];

    return $result;
}


##############################################################################

=head2 message

  $fork->message( $message )

If C<$message> is defined adds that message to the message list.

The messages can be anything. For example an object. But it must be
something that survive L<Storable>.

In scalar context, returns the last message. In list context, returns
all the messages.

=cut

sub message
{
    my( $result, $message ) = @_;

    if( defined $message )
    {
	push @{$result->{'message'}}, $message;
    }
    return wantarray ? @{$result->{'message'}} : $result->{'message'}[-1];
}


##############################################################################

=head2 return

  $fork->return( $message )

If C<$message> is defined, adds it with L</message>.

The complete C<$fork> object is frozen with L<Storable/freeze>,
including all messages added by L</message>. The object is sent to the
PARENT.

The object is retrieved in the PARENT by
L<Para::Frame::Child/get_results> and is there named as the C<$result>
object.

=cut

sub return
{
    my( $result, $message ) = @_;

    debug(1,"Returning child result for $Para::Frame::REQ->{reqnum}")
      if $Para::Frame::REQ;

    $result->message( $message ) if $message;
    my $data = freeze( $result );
#    debug 3, "MD5: ".md5_base64($data);

    my $length = length($data);
    debug(2,"Returning $length bytes of data");

    select STDOUT; $| = 1;  # make unbuffered
    binmode(STDOUT); ## Turn on binmode for STDOUT

#    my $res = print $length . "\0" . $data;
    my $res = print $length . "\0" . $data . "\n";
    if( $res )
    {
#	debug 3, "sent data";
#        debug 1, "Sent ".datadump($result);
    }
    else
    {
	debug "Faild to send data";
    }

    # TODO: Should we wait fot parent to recieve the data?

    exit 0;  # don't forget this
}


##############################################################################

=head2 exception

  $fork->exception( $exception )

  $result->exception

If C<$exception> is defined adds that exception to the exception list.

The exceptions can be anything. For example an object. But it must be
something that survive L<Storable>.

In scalar context, returns the last exception. In list context, returns
all the exceptions.

The PARENT will throw an exception with the last element in this list
after the the CHILD L</return>. That will be done in
L<Para::Frame::Child>.

=cut

sub exception
{
    my( $result, $exception ) = @_;

    if( defined $exception )
    {
	push @{$result->{'exception'}}, $exception;
    }

    return wantarray ? @{$result->{'exception'}} : $result->{'exception'}[0];
}


##############################################################################

=head2 on_return

  $fork->on_return( $codename, @args )

  $fork->on_return

Ads code to be run by the PARENT after the CHILD L</return>.

C<$codename> should be the B<name> of a function to be run. Not a
coderef. The function will be looked for in the caller package. That
is the package that used this method.

Any C<@args> will be passed as params for the function.

If no C<$codename> is given, it just returns the current C<on_return>
value.

In list context, returns a the codename (with package name) and the
params as a list. In scalar context, returns a arrayref to the same
thing.

=cut

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


##############################################################################

=head2 pid

  $fork->pid;

Returns the process id of the child.

=cut

sub pid
{
    my( $result, $pid ) = @_;

    if( defined $pid )
    {
	$result->{'pid'} = $pid;
    }
    return $result->{'pid'};
}


##############################################################################

=head2 status

  $result->status

Returns the status number of the CHILD process.

=cut

sub status
{
    my( $result, $status ) = @_;

    if( defined $status )
    {
	$result->{'status'} = $status;
    }

    return $result->{'status'};
}


##############################################################################

=head2 in_child

  $fork->in_child

Returns true

=cut

sub in_child
{
    return 1;
}


##############################################################################

=head2 in_parent

  $fork->in_parent

Returns false

=cut

sub in_parent
{
    return 0;
}


##############################################################################

1;


=head1 AUTHOR

Jonas Liljegren E<lt>jonas@paranormal.seE<gt>

=head1 SEE ALSO

L<Para::Frame::Request>, L<Para::Frame::Child>

=cut

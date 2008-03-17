#  $Id$  -*-cperl-*-
package Para::Frame::Connection;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2006-2008 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::Connection - Connection class for daemon IPC

=cut

use strict;
use Carp qw( cluck confess );
use POSIX;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump throw );


#######################################################################

=head2 new

  Para::Frame::Connection->new($host)

=cut

sub new
{
    my( $this, $host_in ) = @_;
    my $class = ref($this) || $this;

    my( $host, $port ) = $host_in =~ /^([^:]+):(\d+)$/;
    unless( $port )
    {
	die "Port missing from daemon: $host_in";
    }

    my @cfg =
      (
       PeerAddr => $host,
       PeerPort => $port,
       Proto    => 'tcp',
       Timeout  => 5,
      );

    my $sock = IO::Socket::INET->new(@cfg)
	or die "Can't bind $host:$port : $@\n";

    my $conn = bless
    {
     socket     => $sock,
     host       => $host_in,
     io_select  => IO::Select->new($sock),
    }, $class;

    $conn->reset_buffer;

    # Check the connection...
    #$conn->ping;

    return $conn;
}


#######################################################################

=head2 reset_buffer

=cut

sub reset_buffer
{
    my( $conn ) = @_;

    $conn->{inbuffer} = \ "";
    $conn->{datalength} = undef;
}


#######################################################################

=head2 disconnect

=cut

sub disconnect
{
    my( $conn ) = @_;

    # I/we have stopped using this socket
    $conn->reset_buffer;
    $conn->{'socket'}->shutdown(2);
}


#######################################################################

=head2 ping

=cut

sub ping
{
    my( $conn ) = @_;

    my $res = $conn->get_cmd_val("PING");

    debug "Got $$res";
    return $res;
}


#######################################################################

=head2 get_cmd_val

=cut

sub get_cmd_val
{
    my $conn = shift;
    $conn->send_code( @_ );
    my $res = $conn->get_value;
    unless( $res )
    {
	confess "No result";
    }

    return $res;
}


#######################################################################

=head2 send_code

=cut

sub send_code
{
    debug 2, datadump(\@_);
    my( $conn, $code, $valref, $extra ) = @_;

    die "Too many args in send_code (@_)" if $extra;


    $valref ||= \ "1";

    my $length = length($$valref) + length($code) + 1;
    my $socket = $conn->{'socket'};

    debug 2, "Sending $length - $code - value";
    unless( print $socket "$length\x00$code\x00" . $$valref )
    {
	die "LOST CONNECTION while sending $code\n";
    }
}


#######################################################################

=head2 get_value

=cut

sub get_value
{
    my( $conn ) = @_;

    # Either we know we have something to read
    # or we are expecting an answer shortly

    # This code is adapted from Para::Frame::get_value()

#    debug "Get value from $conn";


    my $time      = time;
    my $timeout   = 5;
    my $io_select = $conn->{io_select};
    my $socket    = $conn->{socket};
    my $inbuffref = $conn->{inbuffref};

  WAITE:
    while(1)
    {
	foreach my $ready ( $io_select->can_read( $timeout ) )
	{
	    last WAITE if $ready == $socket;
	}
	if( time > $time + $timeout )
	{
	    warn "Data timeout!!!";

	    cluck "trace for $socket";
	    throw('action', "Data timeout while talking to client\n");
	}
    }

    # Read data from client.
    my $data='';
    my $rv = $socket->recv($data,POSIX::BUFSIZ, 0);

#    debug "Read data...";

    unless (defined $rv && length $data)
    {
	# EOF from client.
	$conn->disconnect;
	debug "End of file";
	return undef;
    }


    $$inbuffref .= $data;
    unless( $conn->{datalength} )
    {
	debug(4,"Length of record?");
	# Read the length of the data string
	#
	if( $$inbuffref =~ s/^(\d+)\x00// )
	{
#	    debug "Setting length to $1";
	    $conn->{datalength} = $1;
	}
	else
	{
	    debug "Strange INBUFFER content: $$inbuffref";

	    $conn->disconnect;
	    return undef;
	}
    }

    my $datalength = $conn->{datalength};

    unless( $datalength )
    {
	debug "No datalength";

	$conn->reset_buffer;
	return undef;
    }

    my $inbuffer_length = length $$inbuffref;
    unless( $inbuffer_length == $datalength )
    {
	debug "The whole length not yet read ($inbuffer_length of $datalength)";
	if( $inbuffer_length > $datalength )
	{
	    debug "Read too much";
	    $conn->disconnect;
	    return undef;
	}

	debug "Getting more...";
	die "not implemented";
    }


#    debug "The whole length read";

    unless( $$inbuffref =~ s/^(\w+)\x00// )
    {
	debug "No code given: $$inbuffref";
	$conn->reset_buffer;
	return undef;
    }

    my( $code ) = $1;

    if( $code eq 'RESP' )
    {
	debug "RESP recieved ($$inbuffref)";

	$conn->reset_buffer;
	return $inbuffref;
    }
    elsif( $code eq 'PONG' )
    {
	debug "PONG recieved!";
	my $str = "PONG";
	return \$str;
    }
    else
    {
	debug "(Para::Frame::Connection) Strange CODE: $code";
	$conn->reset_buffer;
	return undef;
    }
}


#######################################################################


1;


=head1 AUTHOR

Jonas Liljegren E<lt>jonas@paranormal.seE<gt>

=head1 SEE ALSO

L<Para::Frame>

=cut

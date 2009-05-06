package Para::Frame::Sender;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2009 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Para::Frame::Sender

=cut

use 5.010;
use strict;
use warnings;
use bytes;

use IO::Socket;
use Time::HiRes;

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug );

use constant BUFSIZ => 8192; # Posix buffersize
use constant TRIES    => 20; # 20 connection tries

our $SOCK;

##############################################################################

sub send_to_server
{
    my( $code, $valref ) = @_;

    $valref ||= \ "1";
    my $length_code = length($$valref) + length($code) + 1;

    my $data = "$length_code\x00$code\x00" . $$valref;

    my $length = length($data);
    my $errcnt = 0;
    my $chunk = BUFSIZ;
    my $sent = 0;
    for( my $i=0; $i<$length; $i+= $sent )
    {
	$sent = $SOCK->send( substr $data, $i, $chunk );
	if( $sent )
	{
	    $errcnt = 0;
	}
	else
	{
	    $errcnt++;

	    if( $errcnt >= 10 )
	    {
		debug "Got over 10 failures to send chunk $i";
		debug "LOST CONNECTION";
		return 0;
	    }

	    debug "Resending chunk $i of messge: $data";
	    Time::HiRes::sleep(0.05);
	    redo;
	}
    }

    return 1;
}


##############################################################################

sub connect_to_server
{
    my( $port ) = @_;
 
    # Retry a couple of times

    my @cfg =
	(
	 PeerAddr => 'localhost',
	 PeerPort => $port,
	 Proto    => 'tcp',
	 Timeout  => 5,
	 );

    $SOCK = IO::Socket::INET->new(@cfg);

    my $try = 1;
    while( not $SOCK )
    {
	$try ++;
	debug "Trying again to connect to server ($try)";

	$SOCK = IO::Socket::INET->new(@cfg);

	last if $SOCK;

	if( $try >= TRIES )
	{
	    debug "Tried connecting to port $port $try times - Giving up!";
	    return undef;
	}

	sleep 1;
    }

    binmode( $SOCK, ':raw' );

    debug 2, "Established connection on port $port";

    return $SOCK;
}


##############################################################################

1;


=head1 AUTHOR

Jonas Liljegren E<lt>jonas@paranormal.seE<gt>

=head1 SEE ALSO

L<Para::Frame>, L<Apache>

=cut

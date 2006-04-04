#  $Id$  -*-perl-*-
package Para::Frame::Connection;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Connection class for daemon IPC
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2006 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::Connection - Connection class for daemon IPC

=cut

use strict;
use Data::Dumper;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug );

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
      or die "Failed to connect to $host:$port";

    my $conn = bless
    {
     socket => $sock,
     host => $host_in,
    }, $class;

    $conn->ping;

    return $conn;
}

sub dissconnect
{
    my( $conn ) = @_;

    $conn->{'socket'}->shutdown;
}

sub ping
{
    my( $conn ) = @_;

    my $res = $conn->get_cmd_val("PING");
    return $res;
}

sub get_cmd_val
{
    my $conn = shift;
    $conn->send_code( @_ );
    return Para::Frame::get_value( $Para::Frame::REQ );
}

sub send_code
{
    warn Dumper \@_;
    my( $conn, $code, $valref, $extra ) = @_;

    die "Too many args in send_code (@_)" if $extra;


    $valref ||= \ "1";
    my $client = $Para::Frame::REQ->client;
    my $length = length($$valref) + length($code) + 1;
    my $socket = $conn->{'socket'};

    debug 4, "Sending $length - $code - value";
    unless( print $socket "$length\x00$code\x00" . $$valref )
    {
	die "LOST CONNECTION while sending $code\n";
    }
}


1;


=head1 AUTHOR

Jonas Liljegren E<lt>jonas@paranormal.seE<gt>

=head1 SEE ALSO

L<Para::Frame>

=cut

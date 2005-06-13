#!/usr/bin/perl -w

#  $Id$  -*-perl-*-
package Para::Frame::Client;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework client
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

use strict;
use CGI;
use IO::Socket;
use FreezeThaw qw( freeze );
use Data::Dumper;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n"
	unless $Psi::QUIET;
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug );

our $SOCK;

# $SIG{HUP} = sub { warn "Got a HUP\n"; };
# $SIG{INT} = sub { warn "Got a INT\n"; };
# $SIG{TERM} = sub { warn "Got a TERM\n"; };


sub handler
{
    my( $r ) = @_;

    $|=1;

    debug(1,"$$: Client started");

    my $q = new CGI;

#    die $q->cookie;

#    warn "$$: CGI obj created\n";

    my $port = $r->dir_config('port');

    unless( $port )
    {
	my $errcode = 500;
	my $error = "No port configured for communication with the Paraframe server";
	$r->status_line( $errcode." ".$error );
	$r->no_cache(1);
	$r->send_http_header("text/html");
	$r->print("<html><head><title>$error</title></head><body><h1>$error</h1>\n");
	$r->print("</body></html>\n");
	return 1;
    }

    &connect( $port );

    warn "$$: Socket obj created on port $port\n";

   unless( $SOCK )
   {
       my $errcode = 500;
       my $error = "Can't find the Paraframe server";
       $r->status_line( $errcode." ".$error );
       $r->no_cache(1);
       $r->send_http_header("text/html");
       $r->print("<html><head><title>$error</title></head><body><h1>$error</h1>\n");
       $r->print("<p>The backend server are probably not running</p>");
       $r->print("</body></html>\n");
       return 1;
   };

    debug(1,"$$: Established connection to server");

    my $reqline = $r->the_request;
    warn "$$: Got $reqline\n";

    my $ctype = $r->content_type || 'text/html'; # FIXME
#    my $ctype = $r->content_type or die; # TEST
    if( $ctype =~ /^image/ )
    {
	return 0;
    }
    
    my $params = {};
    foreach my $key ( $q->param )
    {
	$params->{$key} = $q->param_fetch($key);
    }

    my $value = freeze [ $params,  \%ENV, $r->uri, $r->filename, $ctype ];

    send_to_server('REQ', \$value);

    debug(1,"$$: Sent data to server");

    my $in_body = 0;
    my $rows = 0;
    while( $_ = <$SOCK> )
    {
	if( $DEBUG > 4 )
	{
	    my $len = length( $_ );
	    warn "$$: Got: '$_'[$len]\n";
	}

	# Code size max 10 chars
	if( s/^([\w\-]{3,10})\0// )
	{
	    my $code = $1;
	    warn "$$:   Code $code\n";
	    chomp;
	    # Apache Request command execution
	    if( $code eq 'AR-PUT' )
	    {
		my( $cmd, @vals ) = split(/\0/, $_);
		warn "$$: AR-PUT $cmd with @vals\n";
		$r->$cmd( @vals );
	    }
	    # Get filename for this URI
	    elsif( $code eq 'URI2FILE' )
	    {
		my $uri = $_;
		warn "$$: URI2FILE $uri\n";
		my $sr = $r->lookup_uri($uri);
		my $file = $sr->filename;
		send_to_server( 'RESP', \$file );
	    }
	    # Get response of Apace Request command execution
	    elsif( $code eq 'AR-GET' )
	    {
		my( $cmd, @vals ) = split(/\0/, $_);
		warn "$$: AR-GET $cmd with @vals\n";
		my $res =  $r->$cmd( @vals );
		send_to_server( 'RESP', \$res );
	    }
	    # Apache Headers command execution
	    elsif( $code eq 'AT-PUT' )
	    {
		my( $cmd, @vals ) = split(/\0/, $_);
		warn "$$: AT-PUT $cmd with @vals\n";
		my $h = $r->headers_out;
		$h->$cmd( @vals );
	    }
	    else
	    {
		die "Unrecognized code: $code\n";
	    }
	}
	else
	{
	    if( $in_body )
	    {
		$r->print( $_ ) or ( send_to_server("CANCEL") ) and last;
		$rows ++;
	    }
	    else
	    {
		warn "$$: Output the http headers\n";
		my $content_type = $r->content_type;
		unless( $content_type )
		{
		    if( $r->uri =~ /\.tt$/ )
		    {
			$content_type = "text/html";
		    }
		    else
		    {
			$content_type = "text/plain";
		    }
		}
		warn "$$: Content type appears to be $content_type\n";

		$r->send_http_header($content_type);
		$in_body = 1;
	    }
	}
    }

    warn "$$: Returned $rows rows\n";
    debug(1,"$$: Response recieved\n\n\n");

    return 1;
}

sub send_to_server
{
    my( $code, $valref ) = @_;

    my $length = length($$valref) + length($code) + 1;

    debug(1,"$$: Sending $length - $code - value");
    unless( print $SOCK "$length\x00$code\x00" . $$valref )
    {
	die "LOST CONNECTION while sending $code\n";
    }
    return 1;
}

sub connect
{
    my( $port ) = @_;

    $SOCK = new IO::Socket::INET (
				  PeerAddr => 'localhost',
				  PeerPort => $port,
				  Proto => 'tcp',
				  );
}

1;

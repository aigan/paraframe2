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
    print "Loading ".__PACKAGE__." $VERSION\n"
	unless $ENV{'MOD_PERL'};
}

use Para::Frame::Reload;

our $SOCK;
our $r;

our $DEBUG = 1;
our $BACKUP_PORT;

# $SIG{HUP} = sub { warn "Got a HUP\n"; };
# $SIG{INT} = sub { warn "Got a INT\n"; };
# $SIG{TERM} = sub { warn "Got a TERM\n"; };


sub handler
{
    ( $r ) = @_;

    $|=1;

    warn "$$: Client started\n" if $DEBUG;

    my $q = new CGI;

#    die $q->cookie;

#    warn "$$: CGI obj created\n";

    my $dirconfig = $r->dir_config;
    my $port = $dirconfig->{'port'};
    if( $BACKUP_PORT )
    {
	$port = $BACKUP_PORT;
    }

    unless( $port )
    {
	print_error_page("No port configured for communication with the Paraframe server");
	return 1;
    }

    my $reqline = $r->the_request;
    warn "$$: Got $reqline\n" if $DEBUG;

    my $ctype = $r->content_type || 'text/html'; # FIXME
#    my $ctype = $r->content_type or die; # TEST
    if( $ctype =~ /^image/ )
    {
	return 0;
    }

    my @tempfiles = ();
    my $params = {};
    foreach my $key ( $q->param )
    {
	if( $q->upload($key) )
	{
	    warn "$$: param $key is a filehandle\n";
	    my $val = $q->param($key);
	    $params->{$key} = "$val"; # Remove GLOB from value

	    my $keyfile = $key;
	    $keyfile =~ s/[^\w_\-]//; # Make it a normal filename
	    my $dest = "/tmp/paraframe/$$-$keyfile";
	    copy_to_file( $dest, $q->upload($key) ) or return 1;
	    $ENV{"paraframe-upload-$keyfile"} = $dest;
	    push @tempfiles, $dest;
	    warn "$$: Setting ENV paraframe-upload-$keyfile\n";
	}
	else
	{
	    $params->{$key} = $q->param_fetch($key);
	}
    }



    my $value = freeze [ $params,  \%ENV, $r->uri, $r->filename, $ctype, $dirconfig ];

    my $try = 0;
    while()
    {
	$try ++;

	connect_to_server( $port );
	unless( $SOCK )
	{
	    print_error_page("Can't find the Paraframe server",
			     "The backend server are probably not running");
	    last;
	}

	my $rows = 0;
	if( send_to_server('REQ', \$value) )
	{
	    warn "$$: Sent data to server\n" if $DEBUG;
	    $rows = get_response();
	}

	if( $rows )
	{
	    warn "$$: Returned $rows rows\n" if $DEBUG;
	    last;
	}
	else
	{
	    warn "$$: Got no result on try $try\n" if $DEBUG;

	    if( $try >= 3 )
	    {
		print_error_page("Paraframe failed to respond",
				 "I tried three times...");
		last;
	    }

	    sleep 1; # Give server time to recover
	    warn "$$: Trying again...\n" if $DEBUG;
	}
    }

    foreach my $tempfile (@tempfiles)
    {
	warn "$$: Removing tempfile $tempfile\n";
	unlink $tempfile or warn "$$:   failed: $!\n";;
    }

    warn "$$: Done\n\n" if $DEBUG;

    return 1;
}

sub send_to_server
{
    my( $code, $valref ) = @_;

    $valref ||= \ "1";
    my $length = length($$valref) + length($code) + 1;

    warn "$$: Sending $length - $code - value\n" if $DEBUG > 3;
    unless( print $SOCK "$length\x00$code\x00" . $$valref )
    {
	die "LOST CONNECTION while sending $code\n";
    }
    return 1;
}

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
	warn "$$:   Trying again to connect to server ($try)\n" if $DEBUG;

	$SOCK = IO::Socket::INET->new(@cfg);

	last if $SOCK;

#	if( $try >= 20 )
	if( $try >= 3 )
	{
	    warn "$$:   Giving up!\n";
	    return undef;
	}

	sleep 1;
    }

    warn "$$: Established connection on port $port\n" if $DEBUG > 3;
    return $SOCK;
}

sub print_error_page
{
    my( $error, $explain ) = @_;

    $error ||= "Unexplaind error";
    $explain ||= "";
    chomp $explain;

    warn "$$: Returning error: $error\n" if $DEBUG;

    my $dirconfig = $r->dir_config;
    my $path = $r->uri;

    unless( $BACKUP_PORT )
    {
	if( $BACKUP_PORT = $dirconfig->{'backup_port'} )
	{
	    handler($r);
	    $BACKUP_PORT = 0;
	    return;
	}
    }

    if( my $host = $dirconfig->{'backup_redirect'} )
    {
	my $uri_out = "http://$host$path";
	$r->status( 302 );
	$r->header_out('Location', $uri_out );
	$r->send_http_header("text/html");
	$r->print("<p>Try to get <a href=\"$uri_out\">$uri_out</a> instead</p>\n");
	return;
    }

    my $errcode = 500;
    $r->status_line( $errcode." ".$error );
    $r->no_cache(1);
    $r->send_http_header("text/html");
    $r->print("<html><head><title>$error</title></head><body><h1>$error</h1>\n");
    foreach my $row ( split /\n/, $explain )
    {
	$r->print("<p>$row</p>");
	warn "$$:   $row\n" if $DEBUG;
    }

    my $host = $r->hostname;
    $r->print("<p>Try to get <a href=\"$path\">$path</a> again</p>\n");

    if( my $backup = $dirconfig->{'backup'} )
    {
	$r->print("<p>You may want to try <a href=\"http://$backup$path\">http://$backup$path</a> instead</p>\n");
    }

    $r->print("</body></html>\n");
    return 1;
}

sub copy_to_file
{
    my( $filename, $fh ) = @_;

    my $dir = $filename;
    $dir =~ s/\/[^\/]+$//;
    create_dir($dir) unless -d $dir;

    unless( open OUT, ">$filename" )
    {
	warn "$$: Couldn't write to $filename: $!\n";
	print_error_page("Upload error", "Couldn't write to $filename: $!");
	return 0; #failed
    }

    my $buf;
    my $fname; ## Temporary filenames
    my $bufsize = 2048;
    while( (my $len = sysread($fh, $buf, $bufsize)) > 0 )
    {
	print OUT $buf;
    }
    close($fh);
    close(OUT);

    return 1;
}

sub create_dir
{
    my( $dir ) = @_;

    my $parent = $dir;
    $parent =~ s/\/[^\/]+$//;

    unless( -d $parent )
    {
	create_dir( $parent );
    }

    mkdir $dir, 02711;
}

sub get_response
{
    my $in_body = 0;
    my $rows = 0;
    my $chars = 0;
    while( $_ = <$SOCK> )
    {
	if( $DEBUG > 4 )
	{
#	    my $len = length( $_ );
#	    warn "$$: Got: '$_'[$len]\n";
	    $chars += length( $_ );
	}

	# Code size max 10 chars
	if( s/^([\w\-]{3,10})\0// )
	{
	    my $code = $1;
	    warn "$$:   Code $code\n" if $DEBUG;
	    chomp;
	    # Apache Request command execution
	    if( $code eq 'AR-PUT' )
	    {
		my( $cmd, @vals ) = split(/\0/, $_);
		warn "$$: AR-PUT $cmd with @vals\n" if $DEBUG;
		$r->$cmd( @vals );
	    }
	    # Get filename for this URI
	    elsif( $code eq 'URI2FILE' )
	    {
		my $uri = $_;
		warn "$$: URI2FILE $uri\n" if $DEBUG;
		my $sr = $r->lookup_uri($uri);
		my $file = $sr->filename;
		send_to_server( 'RESP', \$file );
	    }
	    # Get response of Apace Request command execution
	    elsif( $code eq 'AR-GET' )
	    {
		my( $cmd, @vals ) = split(/\0/, $_);
		warn "$$: AR-GET $cmd with @vals\n" if $DEBUG;
		my $res =  $r->$cmd( @vals );
		send_to_server( 'RESP', \$res );
	    }
	    # Apache Headers command execution
	    elsif( $code eq 'AT-PUT' )
	    {
		my( $cmd, @vals ) = split(/\0/, $_);
		warn "$$: AT-PUT $cmd with @vals\n" if $DEBUG;
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
		unless( $r->print( $_ ) )
		{
		    warn "$$: Faild to print '$_' after row $rows\n";
		    warn "$$:   Sending CANCEL to server\n";
		    send_to_server("CANCEL");
		    last;
		}
		$rows ++;
	    }
	    else
	    {
		warn "$$: Output the http headers\n" if $DEBUG;
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
		warn "$$: Content type appears to be $content_type\n" if $DEBUG;

		$r->send_http_header($content_type);
		$in_body = 1;
	    }
	}
    }

    warn "$$: Got $chars chars of data\n" if $DEBUG > 4;

    return $rows;
}

1;

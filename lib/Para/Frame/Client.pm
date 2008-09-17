#!/usr/bin/perl -w
#  $Id$  -*-cperl-*-
package Para::Frame::Client;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2008 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::Client - The client for the Request

=cut

use strict;
use bytes;

use CGI;
use IO::Socket;
use IO::Select;
use FreezeThaw qw( freeze );
use Time::HiRes;

# See also
# Apache2::RequestRec
# Apache2::RequestIO
# Apache2::SubRequest
# Apache2::Connection

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n"
	unless $ENV{'MOD_PERL'};
}

use Para::Frame::Reload;

use constant BUFSIZ => 8192; # Posix buffersize
use constant TRIES    => 20; # 20 connection tries
use constant DECLINED => -1; # From httpd.h
use constant DONE     => -2; # From httpd.h

our $DEBUG = 0;

our $SOCK;
our $r;
our $Q;

our $BACKUP_PORT;
our $STARTED; # Got loadpage info at this time
our $LOADPAGE;
our $LOADPAGE_URI;
our $LOADPAGE_TIME;
our $LAST_MESSAGE;
our $WAIT;
our $CANCEL;
our @NOTES;
our $REQNUM;
our $WAITMSG;

=head1 DESCRIPTION

This is the part of L<Para::Frame> that lives in the C<LWP> as a
C<Perl Handler>.

This package is also used by L<Para::Frame> to send messages to
itself, for example from a child to the parent.

The handler takes a lot of information about the request (made by the
browser client calling Apache) and sends it to the paraframe daemon
through a socket. It waits for the finished response page and gives
that page to Apache for sending it back to the browser.

The port for communication with paraframe is taken from the C<port>
variable from Apache dir_config. See L<Apache/SERVER CONFIGURATION
INFORMATION>.

Example; For using port 7788, put in your .htaccess:

  AddHandler perl-script tt
  PerlHandler Para::Frame::Client
  PerlSetVar port 7788

The C<dir_config> hashref is used by paraframe for reading other
variables.

All other dirconfig variables are optional. Here is the list:

=head3 site

The name of the site to use. Useful if you have more than one site on
the same host. This is used by L<Para::Frame::Site>.

Set C<PerlSetVar site ignore> to not handling this request in
paraframe. This is useful for making Apache use the C<DirectoryIndex>
option. And it may be more useful than the C<SetHandler
default-handler> config.

=head3 port

The port to use for communication with the paraframe daemon.

=head3 backup_port

A port to use if the server at the first port doesn't answer.

=head3 backup_redirect

A backup host to use if the paraframe daemon doesn't answer and
neither the backup_port. The same path will be used on the backup
host. It should be the host name, without path and without http. We
will automaticly be redirected to that place.

=head3 backup

If all above fail, we will create a fallback page with a link
suggesting to go to this site. The link is constructad in the same way
as for L</backup_redirect>.

=head2 File uploads

Files will be uploaded in a non-readable directory. The file will be
removed at the end of the request. The file will be readable by the
user and group of the server.  Make sure that the paraframe server is
a member of the main group of the webserver. (That may be
C<www-data>.)

=cut


#######################################################################

sub handler
{
    ( $r ) = @_;

    my $dirconfig = $r->dir_config;

    if( $dirconfig->{'site'} and $dirconfig->{'site'} eq 'ignore' )
    {
	return DECLINED;
    }

    $Q = new CGI;
    $|=1;
    my $ctype = $r->content_type;


    my $uri = $r->uri;
    my $filename = $r->filename;

    my %params = ();
    my %files = ();


    if( $r->isa('Apache2::RequestRec') )
    {
#	warn "Requiering Apache2::SubRequest\n";
	require Apache2::SubRequest;
	Apache2::SubRequest->import();
	require Apache2::Connection;
	Apache2::Connection->import();

	# Unparsed uri keeps multiple // at end of path
	$uri = $r->unparsed_uri;
	$uri =~ s/\?.*//g;
    }

    my $port = $dirconfig->{'port'};
    if( $BACKUP_PORT ) # Is resetted later
    {
	$port = $BACKUP_PORT;
    }
    else
    {
	warn "$$: Client started\n" if $DEBUG;

	unless( $port )
	{
	    print_error_page("No port configured for communication with the Paraframe server");
	    return DONE;
	}
    }

    my $reqline = $r->the_request;
#    warn substr(sprintf("[%s] %d: %s", scalar(localtime), $$, $reqline), 0, 79)."\n";

    ### Optimize for the common case.
    #
    # May be modified in req, but this value guides Loadpage
    #
    warn "$$: Orig ctype $ctype\n" if $ctype and $DEBUG;
    if( not $ctype )
    {
	if( $filename =~ /\.tt$/ )
	{
	    $ctype = 'text/html';
	}
    }
    elsif( $ctype eq "httpd/unix-directory" )
    {
	$ctype = 'text/html';
    }

    unless( $ctype =~ /\bcharset\b/ )
    {
	if( $ctype =~ /^text\// )
	{
	    $ctype .= "; charset=UTF-8";
	}
    }

    $r->content_type($ctype);


    ### We let the daemon decide what to do with non-tt pages


    foreach my $key ( $Q->param )
    {
	if( $Q->upload($key) )
	{
	    warn "$$: param $key is a filehandle\n";

	    my $val = $Q->param($key);
	    my $info = $Q->uploadInfo($val);

	    $params{$key} = "$val"; # Remove GLOB from value

	    my $keyfile = $key;
	    $keyfile =~ s/[^\w_\-]//g; # Make it a normal filename
	    my $dest = "/tmp/paraframe/$$-$keyfile";
	    copy_to_file( $dest, $Q->upload($key) ) or return DONE;

	    my $uploaded =
	    {
	     tempfile => $dest,
	     info     => $info,
	    };

	    $files{$key} = $uploaded;
	}
	else
	{
	    $params{$key} = $Q->param_fetch($key);
	}
    }


    if( my $prev = $r->prev )
    {
	my $pdc = $prev->dir_config;
	if( $pdc->{'renderer'} or $pdc->{'find'} )
	{
	    warn "$$: Consider using SetHandler perl-script in this dir\n";
	}
    }


#    warn sprintf "URI %s FILE %s CTYPE %s\n", $uri, $filename, $ctype;

    my $value = freeze [ \%params,  \%ENV, $uri, $filename, $ctype, $dirconfig, $r->header_only, \%files ];

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

	my $chunks = 0;
	if( send_to_server('REQ', \$value) )
	{
	    warn "$$: Sent data to server\n" if $DEBUG;
	    $chunks = get_response();
	}

	if( $chunks )
	{
	    warn "$$: Returned $chunks chunks\n" if $DEBUG;
	    last;
	}
	elsif( $CANCEL )
	{
	    warn "$$: Closing down CANCELLED request\n";
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

    foreach my $filefield (values %files)
    {
	my $tempfile = $filefield->{tempfile};
	warn "$$: Removing tempfile $tempfile\n";
	unlink $tempfile or warn "$$:   failed: $!\n";;
    }

    warn "$$: Done\n\n" if $DEBUG;

    return DONE;
}


#######################################################################

sub send_to_server
{
    my( $code, $valref ) = @_;

    $valref ||= \ "1";
    my $length_code = length($$valref) + length($code) + 1;

    my $data = "$length_code\x00$code\x00" . $$valref;

#    warn "lengthcode ($length_code) ".(bytes::length($$valref) + bytes::length($code) + 1)."\n";

    if( $DEBUG > 3 )
    {
	warn "$$: Sending string $data\n";
#	warn sprintf "$$:   at %.2f\n", Time::HiRes::time;
    }

    my $length = length($data);
#    warn "$$: Length of block is ($length) ".bytes::length($data)."\n";
    my $errcnt = 0;
    my $chunk = 16384; # POSIX::BUFSIZ * 2
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
		warn "$$: Got over 10 failures to send chunk $i\n";
		warn "$$: LOST CONNECTION\n";
		return 0;
	    }

	    warn "$$:  Resending chunk $i of messge: $data\n";
	    Time::HiRes::sleep(0.05);
	    redo;
	}
    }

    return 1;
}


#######################################################################

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

	if( $try >= TRIES )
	{
	    warn "$$: Tried connecting to port $port $try times - Giving up!\n";
	    return undef;
	}

	sleep 1;
    }

    binmode( $SOCK, ':raw' );

    warn "$$: Established connection on port $port\n" if $DEBUG > 3;
    return $SOCK;
}


#######################################################################

sub print_error_page
{
    my( $error, $explain ) = @_;

    $error ||= "Unexplaind error";
    $explain ||= "";
    chomp $explain;

    my $apache2 = 0;
    if( $r->isa('Apache2::RequestRec') )
    {
	$apache2 = 1;
    }

    warn "$$: Returning error: $error\n" if $DEBUG;

    my $dirconfig = $r->dir_config;
    my $path;
    if( $apache2 )
    {
	$path = $r->unparsed_uri;
    }
    else
    {
	$path = $r->uri;
	if( my $args = $r->args )
	{
	    $path .= '?' . $args;
	}
    }

    unless( $BACKUP_PORT )
    {
	if( $BACKUP_PORT = $dirconfig->{'backup_port'} )
	{
	    warn "$$: Using backup port $BACKUP_PORT\n";
	    handler($r);
	    $BACKUP_PORT = 0;
	    return;
	}
    }

    $r->content_type("text/html");

    if( my $host = $dirconfig->{'backup_redirect'} )
    {
	warn "$$: Refering to backup site\n";
	my $uri_out = "http://$host$path";
	if( $host =~ s/:443$// )
	{
	    $uri_out = "https://$host$path";
	}
	$r->status( 302 );
	$r->headers_out->set('Location', $uri_out );
	$r->send_http_header() unless $apache2;
	$r->print("<p>Try to get <a href=\"$uri_out\">$uri_out</a> instead</p>\n");
	return;
    }

    my $errcode = 500;
    warn "$$: Printing error page\n";
    $r->status_line( $errcode." ".$error );
    $r->no_cache(1);
    $r->send_http_header() unless $apache2;
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
    $r->rflush;

    return 1;
}


#######################################################################

sub copy_to_file
{
    my( $filename, $fh ) = @_;

    my $dir = $filename;
    $dir =~ s/\/[^\/]+$//;
    create_dir($dir) unless -d $dir;

    my $orig_umask = umask;
    umask 07;

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

    umask $orig_umask;
    return 1;
}


#######################################################################

sub create_dir
{
    my( $dir ) = @_;

    my $parent = $dir;
    $parent =~ s/\/[^\/]+$//;

    unless( -d $parent )
    {
	create_dir( $parent );
    }

    my $orig_umask = umask;
    umask 0;
    mkdir $dir, 02711; # 02755?
    umask $orig_umask;
}


#######################################################################

sub get_response
{
    $STARTED = time;
    $LOADPAGE = 0;
    $LOADPAGE_URI = undef;
    $LOADPAGE_TIME = 2;
    $WAIT = 0;
    $LAST_MESSAGE = "";
    @NOTES = ();
    $REQNUM = undef;
    $CANCEL = undef;

    my $timeout = 2.0;


    my $select = IO::Select->new($SOCK);
    my $c = $r->connection;

    my( $apache2, $client_fn, $client_select );

    if( $c->isa('Apache2::Connection') )
    {
	$apache2 = 1;
    }
    else
    {
	$client_fn = $c->fileno(1); # Direction right?!
	$client_select = IO::Select->new($client_fn);
    }

    my $chunks = 0;
    my $data='';
    my $buffer = '';
    my $partial = 0;
    my $buffer_empty_time;
    while( 1 )
    {

	if( $CANCEL )
	{
	    if( ($CANCEL+15) < time )
	    {
		warn "$$: Waited 15 secs\n";
		warn "$$: Closing down\n";
		return 1;
	    }
	}
	else
	{
	    ### Test connection to browser
	    if( $apache2 )
	    {
		if( $c->aborted )
		{
		    warn "$$: Lost connection to client $client_fn\n";
		    warn "$$:   Sending CANCEL to server\n";
		    send_to_server("CANCEL");
		    $CANCEL = time;
		}
	    }
	    elsif( not $client_select->can_write(0)
		   or  $client_select->can_read(0)
		 )
	    {
		warn "$$: Lost connection to client $client_fn\n";
		warn "$$:   Sending CANCEL to server\n";
		send_to_server("CANCEL");
		$CANCEL = time;
	    }
	}


	if( not($data) or $partial )
	{
	    if( $select->can_read( $timeout ) )
	    {
		my $rv = $SOCK->recv($buffer,BUFSIZ, 0);
		unless( defined $rv and length $buffer)
		{
		    if( defined $rv )
		    {
			warn "$$: Buffer empty ($buffer)\n";
			if( $buffer_empty_time )
			{
			    if( ($buffer_empty_time+5) < time )
			    {
				warn "$$: For 5 secs\n";
			    }
			    else
			    {
				sleep 1;
				next;
			    }
			}
			else
			{
			    $buffer_empty_time = time;
			    next;
			}
		    }


		    # EOF from server
		    warn "$$: Nothing in socket $SOCK\n";
		    warn "$$: rv: $rv\n";
		    warn "$$: buffer: $buffer\n";
		    warn "$$: EOF!\n";

		    if( $LOADPAGE )
		    {
			send_message("\nServer vanished!");
			sleep 3;
			send_reload($Q->self_url, "Retrying..." );
		    }
		    last;
		}

		$data .= $buffer;
		$buffer_empty_time = undef;
	    }
	}

	if( $data )
	{
	    my $row;
	    if( $data =~ s/^([^\n]+)\n// )
	    {
		$row = $1;
		$partial = 0;
	    }
	    else
	    {
#		warn "$$: Partial data: $data\n";
		warn "$$: Partial data...\n";
		$partial++;
		next;
	    }

	    if( $DEBUG > 4 )
	    {
		if( my $len = length $data )
		{
		    warn "$$: $len bytes left in databuffer: $data\n";
		}
	    }

	    # Code size max 16 chars
	    # TODO: If in body, this may be part of the body (binary?)
	    if( $row =~ s/^([\w\-]{3,16})\0// )
	    {
		my $code = $1;

#		if( $DEBUG > 3 )
		if( $DEBUG )
		{
		    warn( sprintf "$$: Got %s: %s\n", $code,
			  join '-', split /\0/, $row );
#		    warn sprintf "$$:   at %.2f\n", Time::HiRes::time;
		}


		# Apache Request command execution
		if( $code eq 'AR-PUT' )
		{
		    my( $cmd, @vals ) = split(/\0/, $row);
		    $r->$cmd( @vals );
		}
		# Get filename for this URI
		elsif( $code eq 'URI2FILE' )
		{
		    my $file = uri2file($row);
		    send_to_server( 'RESP', \$file );
		}
		# Get response of Apace Request command execution
		elsif( $code eq 'AR-GET' )
		{
		    my( $cmd, @vals ) = split(/\0/, $row);
		    my $res =  $r->$cmd( @vals );
		    send_to_server( 'RESP', \$res );
		}
		# Apache Headers command execution
		elsif( $code eq 'AT-PUT' )
		{
		    my( $cmd, @vals ) = split(/\0/, $row);
		    my $h = $r->headers_out;
		    $h->$cmd( @vals );
		}
		# Forward to generated page
		elsif( $code eq 'PAGE_READY' )
		{
		    unless( $LOADPAGE )
		    {
			$chunks += send_loadpage()
			  or die "This is not a good place to be";
		    }
		    my( $href, $msg ) = split(/\0/, $row);
		    send_reload($href, $msg);
		    last;
		}
		# Do not send loadpage now
		elsif( $code eq 'WAIT' )
		{
		    my $resp;
		    if( $LOADPAGE )
		    {
			$resp = "LOADPAGE";
		    }
		    else
		    {
			$resp = "SEND";
		    }
		    send_to_server( 'RESP', \ $resp );
		    $WAIT = 1;
		}
		# Do not send loadpage now
		elsif( $code eq 'RESTARTING' )
		{
		    warn "Server restarting\n";
		    $SOCK->shutdown(2);
		    $SOCK->close;

		    if( $BACKUP_PORT = $r->dir_config->{'backup_port'} )
		    {
			warn "$$: Using backup port $BACKUP_PORT\n";
			handler($r);
			$BACKUP_PORT = 0;
			return 1;
		    }

		    sleep 10;
		    return 0; # Tries again...
		}
		# Starting sending body
		elsif( $code eq 'BODY' or
		       $code eq 'HEADER' )
		{
		    if( $LOADPAGE )
		    {
			my $resp = "LOADPAGE";
			send_to_server( 'RESP', \ $resp );
		    }
		    else
		    {
			my $resp = "SEND";
			send_to_server( 'RESP', \ $resp );
			send_headers() or last;
			if( $code eq 'BODY' )
			{
			    $chunks += send_body($data);
			}
			else # HEADER
			{
			    $chunks += 1;
			}

			last;
		    }
		}
		# Retrieving name of loadpage
		elsif( $code eq 'USE_LOADPAGE' )
		{
		    ( $LOADPAGE_URI, $LOADPAGE_TIME, $REQNUM, $WAITMSG ) =
		      split(/\0/, $row);
		    $STARTED = time;
		    $WAITMSG||="";
		    if( $DEBUG > 1 )
		    {
			warn "$$: Loadpage $LOADPAGE_URI in $LOADPAGE_TIME secs\n";
			warn "$$: REQ $REQNUM\n";
		    }
		}
		# Message to display during loading
		elsif( $code eq 'NOTE' )
		{
		    push @NOTES, split(/\0/, $row);
		    if( $LOADPAGE )
		    {
			while( my $note = shift @NOTES )
			{
			    send_message($note);
			}
		    }
		}
		else
		{
		    die "$$: Unrecognized code: $code\n";
		}
	    }
	    else
	    {
		warn "$$: Unrecognized input: $row\n";
		print_error_page("Unrecognized input",$row);
		return 0;
	    }
	}
	elsif( $LOADPAGE )
	{
	    send_message_waiting();
	}


	if( not $LOADPAGE and
	    (time > $STARTED + $LOADPAGE_TIME - 1 ) and
	    $LOADPAGE_URI and
	    ($r->content_type =~ "^text/html" ) and
	    (not $r->header_only ) and
	    not $WAIT
	    )
	{
	    $chunks += send_loadpage();
	    while( my $note = shift @NOTES )
	    {
		send_message($note);
	    }
	}
    }

    return $chunks;
}


#######################################################################

sub send_loadpage
{

    # TODO:
    # We must handle the case then paraframe fails. That should prompt
    # the client to resend the request again, to the reborn demon or
    # to a backup demon. -- In order to resend the request, we must
    # keep the POST data. But if the client returns a ref to a
    # loadpage, the POST data will be lost.

    # On the other hand. In case of a crash, we should probably notify
    # the daemon that, in the case of posts, the visitor should retry
    # the action in the new session.


    # Must be existing page...
    my $sr = $r->lookup_uri($LOADPAGE_URI);
    my $filename = $sr->filename;

    if( open IN, $filename )
    {
	$LOADPAGE = 1;
	send_headers();
	if( $r->isa('Apache2::RequestRec') )
	{
	    my $buffer;

	    while( 1 )
	    {
		# do the read and see how much we got
                my $read_cnt = sysread( IN, $buffer, BUFSIZ ) ;
                if( defined $read_cnt )
		{
		    # good read. see if we hit EOF (nothing left to read)
		    last if $read_cnt == 0 ;

		    $r->print($buffer);
                }
		else
		{
		    warn "$$: Failed to read from '$filename': $!\n";
		    last;
		}
	    }
	}
	else
	{
	    $r->send_fd(*IN);
	}
	close IN;
	$r->rflush;
	send_to_server( 'LOADPAGE' );
	warn "$$: LOADPAGE sent to browser\n";

	while( my $note = shift @NOTES )
	{
	    send_message($note);
	}

	return 1;
    }
    else
    {
	warn "$$: Cant open '$filename': $!\n";
	$WAIT = 1;
    }
}


#######################################################################

sub send_reload
{
    my( $url, $message ) = @_;

    $message ||= "Page Ready!";
    send_message($message);

    warn "$$: Telling browser to reload page\n";


    # More compatible..?
    # self.location.replace('$url');

    $r->print("<script type=\"text/javascript\">window.location.href='$url';</script>");
#    $r->print("<a href=\"$url\">go</a>");
    $r->rflush;
}


#######################################################################

sub send_headers
{
    my $content_type = $r->content_type;
    unless( $content_type )
    {
	print_error_page("Body without content type");
	return 0;
    }

    $r->content_type($content_type);

    return 1 if $r->isa("Apache2::RequestRec");

    $r->send_http_header();
    $r->rflush;
    return 1;
}


#######################################################################

sub send_body
{
    my $data = $_[0] || ''; # From buffer
    warn "$$: Waiting for body\n" if $DEBUG;
    my $select = IO::Select->new($SOCK);
    my $chunk = 1;
    my $timeout = 30; # May have to wait for yield

    if( $DEBUG )
    {
	my $status = $r->status();
	warn "$$: Page status is $status\n";
    }

    unless( length $data )
    {
	warn "$$: Waiting for data\n" if $DEBUG;
	unless( $select->can_read($timeout) )
	{
	    warn "$$: No body ready to be read from $SOCK";
	    return 0;
	}

	unless( $SOCK->read($data, BUFSIZ) )
	{
	    warn "$$: The body was empty\n"; # Problably an empty file
	    return 1;
	}
    }

    while( length $data )
    {
	# Passing scalarrefs is buggy
	if( $DEBUG )
	{
	    my $len = bytes::length($data);
	    warn "$$: Sending $len bytes to browser\n";
	}
	unless( $r->print( $data ) )
	{
	    warn "$$: Faild to send chunk $chunk to client\n";
	    warn "$$:   Sending CANCEL to server\n";
	    send_to_server("CANCEL");
	    return 1;
	}
	warn "$$: Waiting for more data\n" if $DEBUG;
	$SOCK->read($data, BUFSIZ) or last;
	$chunk ++;
    }
    $r->rflush;
    return $chunk;
}


#######################################################################

sub send_message
{
    my( $msg ) = @_;
    $LAST_MESSAGE = $msg;
    chomp $msg;
    $msg =~ s/\n/\\n/g;

    warn "$$: Sending message to browser: $msg\n" if $DEBUG > 1;
    $r->print("<script type=\"text/javascript\">document.forms['f'].messages.value += \"$msg\\n\";bottom();</script>\n");
    $r->rflush;
}


#######################################################################

sub send_message_waiting
{
    return unless length($WAITMSG);

    my $msg = "$WAITMSG \n";
    if( $msg eq $LAST_MESSAGE )
    {
	$r->print("<script type=\"text/javascript\">e=document.forms['f'].messages;e.value = e.value.substring(0,e.value.length-2)+\"..\\n\";bottom();</script>\n");
    $r->rflush;
    }
    else
    {
	send_message($msg);
    }
}


#######################################################################

sub uri2file
{
    my $sr = $r->lookup_uri($_[0]);

    # HACK for reverting dir to file translation if
    # it's index.*
#    warn "Looking up $_[0]\n";
    my $filename = $sr->filename . ($sr->path_info||'');
#    warn "       Got $filename\n";
    if( $filename =~ /\bindex.(\w+)(.*?)$/ )
    {
	my $ext = $1;
	my $tail = $2;
#	warn "  Matched index.* with tail $tail\n";
	if( $_[0] !~ /\bindex.$ext$tail$/ )
	{
	    $filename =~ s/\bindex.$ext$tail$/$tail/;
#	    warn "Trimming filename to $filename\n";
	}
    }

    # TODO: fixme
    # Removes extra slashes
    $filename =~ s(//+)(/)g;

    return( $filename );
}


#######################################################################

1;


=head1 AUTHOR

Jonas Liljegren E<lt>jonas@paranormal.seE<gt>

=head1 SEE ALSO

L<Para::Frame>, L<Apache>

=cut

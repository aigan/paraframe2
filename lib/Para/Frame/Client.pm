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
#   Copyright (C) 2004-2006 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::Client - The client for the Request

=cut

use strict;
use CGI;
use IO::Socket;
use IO::Select;
use FreezeThaw qw( freeze );
use Data::Dumper;
use Apache::Constants qw( :common );
use Time::HiRes;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n"
	unless $ENV{'MOD_PERL'};
}

use Para::Frame::Reload;

use constant BUFSIZ => 8192; # Posix buffersize

our $SOCK;
our $r;

our $DEBUG = 0;
our $BACKUP_PORT;
our $STARTED;
our $LOADPAGE;
our $LOADPAGE_URI;
our $LOADPAGE_TIME;
our $LAST_MESSAGE;
our $WAIT;
our @NOTES;

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

=cut

sub handler
{
    ( $r ) = @_;

    my $dirconfig = $r->dir_config;

    if( $dirconfig->{'site'} and $dirconfig->{'site'} eq 'ignore' )
    {
	return DECLINED;
    }

    my $q = new CGI;
    $|=1;

    warn "$$: Client started\n" if $DEBUG;

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

    ### Optimize for the common case.
    #
    # May be modified in req, but this value guides Loadpage
    #
    my $ctype = $r->content_type;
    warn "$$: Orig ctype $ctype\n" if $ctype;
    if( not $ctype )
    {
	if( $r->filename =~ /\.tt$/ )
	{
	    $ctype = $r->content_type('text/html');
	}
    }
    elsif( $ctype eq "httpd/unix-directory" )
    {
	$ctype = $r->content_type('text/html');
    }
    else
    {
	warn "$$: declining $ctype\n";
	return DECLINED;
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
	    $keyfile =~ s/[^\w_\-]//g; # Make it a normal filename
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



    my $value = freeze [ $params,  \%ENV, $r->uri, $r->filename, $ctype, $dirconfig, $r->header_only ];

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

    if( $DEBUG > 3 )
    {
	warn "$$: Sending $length - $code - $$valref\n";
#	warn sprintf "$$:   at %.2f\n", Time::HiRes::time;
    }
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
    mkdir $dir, 02711;
    umask $orig_umask;
}

sub get_response
{
    $STARTED = time;
    $LOADPAGE = 0;
    $LOADPAGE_URI = undef;
    $LOADPAGE_TIME = 2;
    $WAIT = 0;
    $LAST_MESSAGE = "";
    @NOTES = ();

#    my $timeout_long = 1.5;
#    my $timeout_short = 0.001;
#    my $timeout = $timeout_short;
    my $timeout = 1.5;


    my $select = IO::Select->new($SOCK);
    my $c = $r->connection;
    my $client_fn = $c->fileno(0); # Direction right?!
#    warn "$$: Client output filenumber is $client_fn\n";
    my $client_fh = IO::Handle->new_from_fd($client_fn,'w');

    unless( $client_fh ) # Lost connection
    {
	warn "$$: Lost connection to client $client_fn\n";
	warn "$$:   Sending CANCEL to server\n";
	send_to_server("CANCEL");
	return 1;
    }

#    warn "$$: Client output filehandle is $client_fh\n";
    my $client_select = IO::Select->new($client_fh);
#    warn "$$: Client output select is $client_select\n";

    my $chunks = 0;
    my $data='';
    my $buffer = '';
    while( 1 )
    {
	unless( $data )
	{
	    if( $select->can_read( $timeout ) )
	    {
		my $rv = $SOCK->recv($buffer,BUFSIZ, 0);
		unless( defined $rv and length $buffer)
		{
		    # EOF from client
		    warn "$$: Nothing in socket $SOCK\n";
		    warn "$$: rv: ".Dumper($rv);
		    warn "$$: buffer: ".Dumper($buffer);
		    warn "$$: EOF!\n";
		    last;
		}

		$data .= $buffer;
	    }
	}

	if( $data )
	{
	    my $row;
	    if( $data =~ s/^([^\n]+)\n// )
	    {
		$row = $1;
	    }
	    else
	    {
		warn "$$: Partial data: $data\n";
		next;
	    }

	    if( $DEBUG > 3 )
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

		if( $DEBUG > 4 )
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
		    my $uri = $row;
		    my $sr = $r->lookup_uri($uri);
		    my $file = $sr->filename;
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
			$chunks += send_loadpage();
		    }
		    send_reload($row);
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
			    $chunks += send_body();
			}
			else # HEADER
			{
			    $chunks += 1;
			}

			last;
		    }
		}
		elsif( $code eq 'LOADPAGE' )
		{
		    ( $LOADPAGE_URI, $LOADPAGE_TIME ) =
		      split(/\0/, $row);
		    warn "$$: Loadpage $LOADPAGE_URI in $LOADPAGE_TIME secs\n";
		}
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
	else
	{
	    if( $LOADPAGE )
	    {
		send_message_waiting();
		while( my $note = shift @NOTES )
		{
		    send_message($note);
		}
	    }
	    elsif( $LOADPAGE_URI and
		   ($r->content_type eq "text/html" ) and
		   (time > $STARTED + $LOADPAGE_TIME - 1 ) and
		   (not $r->header_only ) and
		   not $WAIT
		 )
	    {
		send_to_server( 'LOADPAGE' );
		$chunks += send_loadpage();
	    }
	}
    }

    return $chunks;
}

sub send_loadpage
{
    my $sr = $r->lookup_uri($LOADPAGE_URI);
    my $filename = $sr->filename;
    if( open IN, $filename )
    {
	$LOADPAGE = 1;
	send_headers();
	$r->print(<IN>) or die $!;
	close IN;
	$r->rflush;
	warn "$$: LOADPAGE sent to browser\n";

	while( my $note = shift @NOTES )
	{
	    send_message($note);
	}

	return 1;
    }
    else
    {
	die "$$: Cant open '$filename': $!\n";
    }
}

sub send_reload
{
    my( $url ) = @_;
    send_message("Page Ready!");

    warn "$$: Tell browser to reload page\n";
    $r->print("<script type=\"text/javascript\">window.location.href='$url';</script>");
    $r->rflush;
}

sub send_headers
{
    my $content_type = $r->content_type;
    unless( $content_type )
    {
	print_error_page("Body without content type");
	return 0;
    }
    $r->send_http_header($content_type);
    $r->rflush;
    return 1;
}

sub send_body
{
    warn "$$: Waiting for body\n";
    my $select = IO::Select->new($SOCK);
    my $data = '';
    my $chunk = 1;
    my $timeout = 30; # May have to wait for yield
    
    unless( $select->can_read($timeout) )
    {
	die "No body ready to be read from $SOCK";
    }

    $SOCK->read($data, BUFSIZ) or die "No body to send";

    while( length $data )
    {
	unless( $r->print( \$data ) )
	{
	    warn "$$: Faild to send chunk $chunk to client\n";
	    warn "$$:   Sending CANCEL to server\n";
	    send_to_server("CANCEL");
	    return 1;
	}
	$SOCK->read($data, BUFSIZ) or last;
	$chunk ++;
    }
    $r->rflush;
    return $chunk;
}

sub send_message
{
    my( $msg ) = @_;
    $LAST_MESSAGE = $msg;
    chomp $msg;
    $msg =~ s/\n/\\n/g;

    warn "$$: Sending message to browser: $msg\n";
    $r->print("<script type=\"text/javascript\">document.f.messages.value += \"$msg\\n\";bottom();</script>\n");
    $r->rflush;
}

sub send_message_waiting
{
    my $msg = "Processing...";
    if( $msg eq $LAST_MESSAGE )
    {
	$r->print("<script type=\"text/javascript\">e=document.f.messages;e.value = e.value.substring(0,e.value.length-1)+\".\\n\";bottom();</script>\n");
    $r->rflush;
    }
    else
    {
	send_message($msg);
    }
}

1;


=head1 AUTHOR

Jonas Liljegren E<lt>jonas@paranormal.seE<gt>

=head1 SEE ALSO

L<Para::Frame>, L<Apache>

=cut

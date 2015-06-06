package Para::Frame::Client;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2010 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Para::Frame::Client - The client for the Request

=cut

use 5.010;
use strict;
use warnings;
use bytes;

use CGI;
use IO::Socket;
use IO::Select;
use Storable qw( freeze );
use Time::HiRes;
use Apache2::RequestRec;
use Apache2::Connection;
use Apache2::SubRequest;
use Apache2::ServerUtil;
use Apache2::RequestIO;
use Apache2::Const -compile => qw( DECLINED DONE );

use Para::Frame::Reload;

use constant BUFSIZ => 8192;    # Posix buffersize
use constant TRIES    => 20;    # 20 connection tries

our $DEBUG = 0;


our $SOCK;
our $r;
our $Q;

our $BACKUP_PORT;
our $STARTED;                   # Got loadpage info at this time
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


##############################################################################

sub handler
{
    ( $r ) = @_;
    my $s = Apache2::ServerUtil->server;

    my $dirconfig = $r->dir_config;
    my $method = $r->method;

    if ( $dirconfig->{'site'} and $dirconfig->{'site'} eq 'ignore' )
    {
        return Apache2::Const::DECLINED;
    }

    if ( $method !~ /^(GET|HEAD|POST)$/ )
    {
        return Apache2::Const::DECLINED;
    }

    $Q = new CGI;
    $|=1;
    my $ctype = $r->content_type;

    my $filename = $r->filename;

    my %params = ();
    my %files = ();


    # Unparsed uri keeps multiple // at end of path
    my $uri = $r->unparsed_uri;
    $uri =~ s/\?.*//g;


    my $port = $dirconfig->{'port'};
    if ( $Q->param('pfport') )
    {
        $port = $Q->param('pfport');
    }
    elsif ( $BACKUP_PORT )      # Is resetted later
    {
        $port = $BACKUP_PORT;
    }
    else
    {
        $s->log_error("$$: Client started") if $DEBUG;

        unless( $port )
        {
            print_error_page("No port configured for communication with the Paraframe server");
            return Apache2::Const::DONE;
        }
    }

    my $reqline = $r->the_request;
    warn substr(sprintf("[%s] %d: %s", scalar(localtime), $$, $reqline), 0, 1023)."\n";

    ### Optimize for the common case.
    #
    # May be modified in req, but this value guides Loadpage
    #
    $s->log_error("$$: Orig ctype $ctype") if $ctype and $DEBUG;
    if ( not $ctype )
    {
        if ( $filename =~ /\.tt$/ )
        {
            $ctype = 'text/html';
        }
    }
    elsif ( $ctype eq "httpd/unix-directory" )
    {
        $ctype = 'text/html';
    }

    if ( $ctype )
    {
        unless( $ctype =~ /\bcharset\b/ )
        {
            if ( $ctype =~ /^text\// )
            {
                $ctype .= "; charset=UTF-8";
            }
        }

        $r->content_type($ctype);
    }


    ### We let the daemon decide what to do with non-tt pages


    foreach my $key ( $Q->param )
    {
        if ( $Q->upload($key) )
        {
            $s->log_error("$$: param $key is a filehandle");

            my $val = $Q->param($key);
            my $info = $Q->uploadInfo($val);

            $params{$key} = "$val"; # Remove GLOB from value

            my $keyfile = $key;
            $keyfile =~ s/[^\w_\-]//g; # Make it a normal filename
            my $dest = "/tmp/paraframe/$$-$keyfile";
            copy_to_file( $dest, $Q->upload($key) ) or return Apache2::Const::DONE;

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


    if ( my $prev = $r->prev )
    {
        my $pdc = $prev->dir_config;
        if ( $pdc->{'renderer'} or $pdc->{'find'} )
        {
            $s->log_error("$$: Consider using SetHandler perl-script in this dir");
        }
    }


#    warn sprintf "URI %s FILE %s CTYPE %s\n", $uri, $filename, $ctype;

    my $value = freeze [ \%params,  \%ENV, $uri, $filename, $ctype, {%$dirconfig}, $r->header_only, \%files, $r->status ];

    my $try = 0;
    while ()
    {
        $try ++;
        my $chunks = 0;

        connect_to_server( $port );
        eval
        {
            unless( $SOCK )
            {
                print_error_page("Can't find the Paraframe server",
                                 "The backend server are probably not running");
                return 0;
            }

            if ( send_to_server('REQ', \$value) )
            {
                $s->log_error("$$: Sent data to server") if $DEBUG;
                $chunks = get_response();
            }
            1;
        } or last;
        if ( $@ )
        {
            $s->log_error($@);
        }

        if ( $CANCEL )
        {
            $s->log_error("$$: Closing down CANCELLED request");
            last;
        }
        elsif ( $chunks )
        {
            $s->log_error("$$: Returned $chunks chunks") if $DEBUG;
            last;
        }
        else
        {
            $s->log_error("$$: Got no result on try $try") if $DEBUG;

            if ( $try >= 3 )
            {
                print_error_page("Paraframe failed to respond",
                                 "I tried three times...");
                last;
            }

            sleep 1;            # Give server time to recover
            $s->log_error("$$: Trying again...") if $DEBUG;
        }
    }

    foreach my $filefield (values %files)
    {
        my $tempfile = $filefield->{tempfile};
        $s->log_error("$$: Removing tempfile $tempfile");
        unlink $tempfile or $s->log_error("$$:   failed: $!");;
    }

    $s->log_error("$$: Done") if $DEBUG;

    return Apache2::Const::DONE;
}


##############################################################################

sub send_to_server
{
    my( $code, $valref ) = @_;
    my $s = Apache2::ServerUtil->server;

    $valref ||= \ "1";
    my $length_code = length($$valref) + length($code) + 1;

    my $data = "$length_code\x00$code\x00" . $$valref;

#    $s->log_error("lengthcode ($length_code) ".(bytes::length($$valref) + bytes::length($code) + 1)."");

    if ( $DEBUG > 3 )
    {
        my $data_debug = $data;
        $data_debug =~ s/\x00/<NUL>/g;
        $s->log_error("$$: Sending string $data_debug");
#	$s->log_error(sprintf "$$:   at %.2f"), Time::HiRes::time;
    }

    my $length = length($data);
#    $s->log_error("$$: Length of block is ($length) ".bytes::length($data)."");
    my $errcnt = 0;
    my $chunk = 16384;          # POSIX::BUFSIZ * 2
    my $sent = 0;
    for ( my $i=0; $i<$length; $i+= $sent )
    {
        $sent = $SOCK->send( substr $data, $i, $chunk );
        if ( $sent )
        {
            $errcnt = 0;
        }
        else
        {
            $errcnt++;

            if ( $errcnt >= 10 )
            {
                $s->log_error("$$: Got over 10 failures to send chunk $i");
                $s->log_error("$$: LOST CONNECTION");
                return 0;
            }

            $s->log_error("$$:  Resending chunk $i of messge: $data");
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
    my $s = Apache2::ServerUtil->server;

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
    while ( not $SOCK )
    {
        $try ++;
        $s->log_error("$$:   Trying again to connect to server ($try)") if $DEBUG;

        $SOCK = IO::Socket::INET->new(@cfg);

        last if $SOCK;

        if ( $try >= TRIES )
        {
            $s->log_error("$$: Tried connecting to port $port $try times - Giving up!");
            return undef;
        }

        sleep 1;
    }

    binmode( $SOCK, ':raw' );

    $s->log_error("$$: Established connection on port $port") if $DEBUG > 3;
    return $SOCK;
}


##############################################################################

sub print_error_page
{
    my( $error, $explain ) = @_;
    my $s = Apache2::ServerUtil->server;

    $error ||= "Unexplaind error";
    $explain ||= "";
    chomp $explain;

    $s->log_error("$$: Returning error: $error") if $DEBUG;

    my $dirconfig = $r->dir_config;
    my $path;
    $path = $r->unparsed_uri;

    unless( $BACKUP_PORT )
    {
        if ( $BACKUP_PORT = $dirconfig->{'backup_port'} )
        {
            $s->log_error("$$: Using backup port $BACKUP_PORT");
            handler($r);
            $BACKUP_PORT = 0;
            return;
        }
    }

    $r->content_type("text/html");

    if ( my $host = $dirconfig->{'backup_redirect'} )
    {
        $s->log_error("$$: Refering to backup site");
        my $uri_out = "http://$host$path";
        if ( $host =~ s/:443$// )
        {
            $uri_out = "https://$host$path";
        }
        $r->status( 302 );
        $r->headers_out->set('Location', $uri_out );
        rprint("<p>Try to get <a href=\"$uri_out\">$uri_out</a> instead</p>\n");
        return;
    }

    my $errcode = 500;
    $s->log_error("$$: Printing error page");
    $r->status_line( $errcode." ".$error );
    $r->no_cache(1);
    rprint("<html><head><title>$error</title></head><body><h1>$error</h1>\n");
    foreach my $row ( split /\n/, $explain )
    {
        rprint("<p>$row</p>");
        $s->log_error("$$:   $row") if $DEBUG;
    }

    my $host = $r->hostname;
    rprint("<p>Try to get <a href=\"$path\">$path</a> again</p>\n");

    if ( my $backup = $dirconfig->{'backup'} )
    {
        rprint("<p>You may want to try <a href=\"http://$backup$path\">http://$backup$path</a> instead</p>\n");
    }

    rprint("</body></html>\n");
    $r->rflush;

    return 1;
}


##############################################################################

  sub copy_to_file
{
    my( $filename, $fh ) = @_;
    my $s = Apache2::ServerUtil->server;

    my $dir = $filename;
    $dir =~ s/\/[^\/]+$//;
    create_dir($dir) unless -d $dir;

    my $orig_umask = umask;
    umask 07;

    unless( open OUT, ">$filename" )
    {
        $s->log_error("$$: Couldn't write to $filename: $!");
        print_error_page("Upload error", "Couldn't write to $filename: $!");
        return 0;               #failed
    }

    my $buf;
    my $fname;                  ## Temporary filenames
    my $bufsize = 2048;
    while ( (my $len = sysread($fh, $buf, $bufsize)) > 0 )
    {
        print OUT $buf;
    }
    close($fh);
    close(OUT);

    umask $orig_umask;
    return 1;
}


##############################################################################

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
    mkdir $dir, 02710; # Dir not listable. But files inside it accessible
    umask $orig_umask;
}


##############################################################################

sub get_response
{
    my $s = Apache2::ServerUtil->server;

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

    my $chunks = 0;
    my $data='';
    my $buffer = '';
    my $partial = 0;
    my $buffer_empty_time;
    while ( 1 )
    {

        if ( $CANCEL )
        {
            if ( ($CANCEL+15) < time )
            {
                $s->log_error("$$: Waited 15 secs");
                $s->log_error("$$: Closing down");
                return 1;
            }
        }
        else
        {
            ### Test connection to browser
            if ( $c->aborted )
            {
                my $client_fn = $c->get_remote_host;
                $s->log_error("$$: Lost connection to client $client_fn");
                $s->log_error("$$:   Sending CANCEL to server");
                send_to_server("CANCEL");
                $CANCEL = time;
            }
        }


        if ( not($data) or $partial )
        {
            if ( $select->can_read( $timeout ) )
            {
                my $rv = $SOCK->recv($buffer,BUFSIZ, 0);
                unless( defined $rv and length $buffer)
                {
                    if ( defined $rv )
                    {
                        $s->log_error("$$: Buffer empty");
                        if ( $buffer_empty_time )
                        {
                            if ( ($buffer_empty_time+5) < time )
                            {
                                $s->log_error("$$: For 5 secs");
                                $s->log_error("$$: Socket $SOCK");
                                $s->log_error("$$: atmark ".$SOCK->atmark);
                                $s->log_error("$$: connected ".$SOCK->connected);

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
#		    $s->log_error("$$: Nothing in socket $SOCK");
#		    $s->log_error("$$: rv: $rv");
#		    $s->log_error("$$: buffer: $buffer");
                    $s->log_error("$$: EOF!");

                    if ( $LOADPAGE )
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

        if ( $data )
        {
            my $row;
            if ( $data =~ s/^([^\n]+)\n// )
            {
                $row = $1;
                $partial = 0;
            }
            else
            {
#		$s->log_error("$$: Partial data: $data");
                $s->log_error("$$: Partial data...");
                $partial++;
                next;
            }

            if ( $DEBUG > 4 )
            {
                if ( my $len = length $data )
                {
                    $s->log_error("$$: $len bytes left in databuffer: $data");
                }
            }

            # Code size max 16 chars
            # TODO: If in body, this may be part of the body (binary?)
            if ( $row =~ s/^([\w\-]{3,16})\0// )
            {
                my $code = $1;

#		if( $DEBUG > 3 )
                if ( $DEBUG )
                {
                    $s->log_error( sprintf "$$: Got %s: %s", $code,
                                   join '-', split /\0/, $row );
#		    $s->log_error(sprintf "$$:   at %.2f"), Time::HiRes::time;
                }


                # Apache Request command execution
                if ( $code eq 'AR-PUT' )
                {
                    my( $cmd, @vals ) = split(/\0/, $row);
                    $r->$cmd( @vals );
                }
                # Get filename for this URI
                elsif ( $code eq 'URI2FILE' )
                {
                    my $file = uri2file($row);
                    send_to_server( 'RESP', \$file );
                }
                # Get response of Apace Request command execution
                elsif ( $code eq 'AR-GET' )
                {
                    my( $cmd, @vals ) = split(/\0/, $row);
                    my $res =  $r->$cmd( @vals );
                    send_to_server( 'RESP', \$res );
                }
                # Apache Headers command execution
                elsif ( $code eq 'AT-PUT' )
                {
                    my( $cmd, @vals ) = split(/\0/, $row);
                    my $h = $r->headers_out;
                    $h->$cmd( @vals );
                }
                # Forward to generated page
                elsif ( $code eq 'PAGE_READY' )
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
                elsif ( $code eq 'WAIT' )
                {
                    my $resp;
                    if ( $LOADPAGE )
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
                elsif ( $code eq 'RESTARTING' )
                {
                    $s->log_error("Server restarting");
                    $SOCK->shutdown(2);
                    $SOCK->close;

                    if ( $BACKUP_PORT = $r->dir_config->{'backup_port'} )
                    {
                        $s->log_error("$$: Using backup port $BACKUP_PORT");
                        handler($r);
                        $BACKUP_PORT = 0;
                        return 1;
                    }

                    sleep 10;
                    return 0;   # Tries again...
                }
                # Starting sending body
                elsif ( $code eq 'BODY' or
                        $code eq 'HEADER' )
                {
                    if ( $LOADPAGE )
                    {
                        my $resp = "LOADPAGE";
                        send_to_server( 'RESP', \ $resp );
                    }
                    else
                    {
                        my $resp = "SEND";
                        send_to_server( 'RESP', \ $resp );
                        send_headers() or last;
                        if ( $code eq 'BODY' )
                        {
                            $chunks += send_body($data);
                        }
                        else    # HEADER
                        {
                            $chunks += 1;
                        }

                        last;
                    }
                }
                # Retrieving name of loadpage
                elsif ( $code eq 'USE_LOADPAGE' )
                {
                    ( $LOADPAGE_URI, $LOADPAGE_TIME, $REQNUM, $WAITMSG ) =
                      split(/\0/, $row);
                    $STARTED = time;
                    $WAITMSG||="";
                    if ( $DEBUG > 1 )
                    {
                        $s->log_error("$$: Loadpage $LOADPAGE_URI in $LOADPAGE_TIME secs");
                        $s->log_error("$$: REQ $REQNUM");
                    }
                }
                # Message to display during loading
                elsif ( $code eq 'NOTE' )
                {
                    push @NOTES, split(/\0/, $row);
                    if ( $LOADPAGE )
                    {
                        while ( my $note = shift @NOTES )
                        {
                            send_message($note);
                        }
                    }
                }
                else
                {
                    die "$$: Unrecognized code: $code";
                }
            }
            else
            {
                $s->log_error("$$: Unrecognized input: $row");
                print_error_page("Unrecognized input",$row);
                return 0;
            }
        }
        elsif ( $LOADPAGE )
        {
            send_message_waiting();
        }


        if ( not $LOADPAGE and
             (time > $STARTED + $LOADPAGE_TIME - 1 ) and
             $LOADPAGE_URI and
             ($r->content_type =~ "^text/html" ) and
             (not $r->header_only ) and
             not $WAIT
           )
        {
            $chunks += send_loadpage();
            while ( my $note = shift @NOTES )
            {
                send_message($note);
            }
        }
    }

    return $chunks;
}


##############################################################################

sub send_loadpage
{
    my $s = Apache2::ServerUtil->server;

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

    if ( open IN, $filename )
    {
        $LOADPAGE = 1;
        send_headers();
        my $buffer;

        while ( 1 )
        {
            # do the read and see how much we got
            my $read_cnt = sysread( IN, $buffer, BUFSIZ ) ;
            if ( defined $read_cnt )
            {
                # good read. see if we hit EOF (nothing left to read)
                last if $read_cnt == 0 ;

                rprint($buffer);
            }
            else
            {
                $s->log_error("$$: Failed to read from '$filename': $!");
                last;
            }
        }
        close IN;
        $r->rflush;
        send_to_server( 'LOADPAGE' );
        $s->log_error("$$: LOADPAGE sent to browser");

        while ( my $note = shift @NOTES )
        {
            send_message($note);
        }

        return 1;
    }
    else
    {
        $s->log_error("$$: Cant open '$filename': $!");
        $WAIT = 1;
    }
}


##############################################################################

sub send_reload
{
    my( $url, $message ) = @_;
    my $s = Apache2::ServerUtil->server;

    $message ||= "Page Ready!";
    send_message($message);

    $s->log_error("$$: Telling browser to reload page");


    # More compatible..?
    # self.location.replace('$url');

    rprint("<script>window.location.href='$url';</script>");
#    $r->print("<a href=\"$url\">go</a>");
    $r->rflush;
}


##############################################################################

sub send_headers
{
    my $content_type = $r->content_type;
    unless( $content_type )
    {
        print_error_page("Body without content type");
        return 0;
    }

    $r->content_type($content_type);

    return 1;
}


##############################################################################

sub send_body
{
    my $data = $_[0] || '';     # From buffer
    my $s = Apache2::ServerUtil->server;
    $s->log_error("$$: Waiting for body") if $DEBUG;
    my $select = IO::Select->new($SOCK);
    my $chunk = 1;
    my $timeout = 30;           # May have to wait for yield

    if ( $DEBUG )
    {
        my $status = $r->status();
        $s->log_error("$$: Page status is $status");
    }

    unless( length $data )
    {
        $s->log_error("$$: Waiting for data") if $DEBUG;
        unless( $select->can_read($timeout) )
        {
            $s->log_error("$$: No body ready to be read from $SOCK");
            return 0;
        }

        unless( $SOCK->read($data, BUFSIZ) )
        {
            $s->log_error("$$: The body was empty"); # Problably an empty file
            return 1;
        }
    }

    while ( length $data )
    {
        # Passing scalarrefs is buggy
        if ( $DEBUG )
        {
            my $len = bytes::length($data);
            $s->log_error("$$: Sending $len bytes to browser");
        }
        unless( $r->print( $data ) )
        {
            $s->log_error("$$: Faild to send chunk $chunk to client");
            $s->log_error("$$:   Sending CANCEL to server");
            send_to_server("CANCEL");
            $CANCEL = time;
            return 0;
        }
        $s->log_error("$$: Waiting for more data") if $DEBUG;
        $SOCK->read($data, BUFSIZ) or last;
        $chunk ++;
    }
    $r->rflush;
    return $chunk;
}


##############################################################################

sub send_message
{
    my( $msg ) = @_;
    my $s = Apache2::ServerUtil->server;
    $LAST_MESSAGE = $msg;
    chomp $msg;
    $msg =~ s/\n/\\n/g;

    $s->log_error("$$: Sending message to browser: $msg") if $DEBUG > 1;
    rprint("<script>document.forms['f'].messages.value += \"$msg\\n\";bottom();</script>\n");
    $r->rflush;
}


##############################################################################

sub send_message_waiting
{
    return unless length($WAITMSG);

    my $msg = "$WAITMSG \n";
    if ( $msg eq $LAST_MESSAGE )
    {
        rprint("<script>e=document.forms['f'].messages;e.value = e.value.substring(0,e.value.length-2)+\"..\\n\";bottom();</script>\n");
        $r->rflush;
    }
    else
    {
        send_message($msg);
    }
}


##############################################################################

sub uri2file
{
    my $sr = $r->lookup_uri($_[0]);

    # HACK for reverting dir to file translation if
    # it's index.*
#    $s->log_error("Looking up $_[0]");
    my $filename = $sr->filename . ($sr->path_info||'');

    unless( $filename )
    {
        if( $sr->status != 200 )
        {
            my $s = Apache2::ServerUtil->server;
            $s->log_error("uri2file $_[0] resulted in ".$sr->status);
            return '';
        }
    }

#    $s->log_error("       Got $filename");
    if ( $filename =~ /\bindex.(\w+)(.*?)$/ )
    {
        my $ext = $1;
        my $tail = $2;
#	$s->log_error("  Matched index.* with tail $tail");
        if ( $_[0] !~ /\bindex.$ext$tail$/ )
        {
            $filename =~ s/\bindex.$ext$tail$/$tail/;
#	    $s->log_error("Trimming filename to $filename");
        }
    }

    # TODO: fixme
    # Removes extra slashes
    $filename =~ s(//+)(/)g;

    return( $filename );
}


##############################################################################

sub rprint
{
    unless( $r->print( @_ ) )
    {
        send_to_server("CANCEL");
        $CANCEL = time;
        die "cancel\n";
    }
    return 1;
}

##############################################################################

1;


=head1 AUTHOR

Jonas Liljegren E<lt>jonas@paranormal.seE<gt>

=head1 SEE ALSO

L<Para::Frame>, L<Apache>

=cut

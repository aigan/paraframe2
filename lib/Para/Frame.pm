#  $Id$  -*-perl-*-
package Para::Frame;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework server
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

=head1 NAME

Para::Frame - Web application framework

=cut

use 5.008;
use strict;
use IO::Socket 1.18;
use IO::Select;
use Socket;
use POSIX qw( locale_h );
use Text::Autoformat; #exports autoformat()
use Time::HiRes qw( time );
use Data::Dumper;
use Carp qw( cluck confess carp croak );
use Sys::CpuLoad;
use DateTime::TimeZone;

our $VERSION;
our $CVSVERSION;

BEGIN
{
    $CVSVERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    $VERSION = "1.03"; # Paraframe version
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Watchdog;
use Para::Frame::Request;
use Para::Frame::Widget;
use Para::Frame::Burner;
use Para::Frame::Time qw( now );
use Para::Frame::Utils qw( throw catch run_error_hooks debug create_file chmod_file fqdn );
use Para::Frame::Email::Address;

use constant TIMEOUT_LONG  =>   5;
use constant TIMEOUT_SHORT =>   0.001;
use constant BGJOB_MAX     =>   8;      # At most
use constant BGJOB_MED     =>  60 *  5; # Even if no visitors
use constant BGJOB_MIN     =>  60 * 15; # At least this often
use constant BGJOB_CPU     =>   0.8;

# Do not init variables here, since this will be redone each time code is updated
our $SERVER     ;
our $DEBUG      ;
our $INDENT     ;
our @JOBS       ;
our %REQUEST    ;
our $REQ        ;
our $REQ_LAST   ;  # Remeber last $REQ beyond a undef $REQ
our $U          ;
our $REQNUM     ;
our %SESSION    ;
our %USER       ;
our $SELECT     ;
our %INBUFFER   ;
our %DATALENGTH ;
our $CFG        ;
our %HOOK       ;
our $PARAMS     ;
our %CHILD      ;
our $LEVEL      ;
our $BGJOBDATE  ;
our $BGJOBNR    ;
our @BGJOBS_PENDING;       # New jobs to be added in background
our $TERMINATE  ;
our $IN_STARTUP;           # True until we reach the watchdog loop
our $ACTIVE_PIDFILE;       # The PID indicated by existing pidfile
our $LAST       ;          # The last entering of the main loop

# STDOUT goes to the watchdog. Use well defined messages!
# STDERR goes to the log

=head1 DESCRIPTION

Para::Frame is a system to use for dynamic web sites. It runs as a
backend daemon taking page requests from a Apache mod_perl client and
returns a HTTP response.


=over


=item L<Para::Frame::Overview>

Overview and Introduction


=item L<Para::Frame::Template::Overview>

The default ParaFrame TT components


=item L<Para::Frame::Template::Meta>

The page META information


=item L<Para::Frame::Template::Index>

Template creation and modification


=back

=head1 QUICKSTART

In httpd.conf :

   <Perl>
      unshift @INC, '/usr/local/paraframe/lib';
   </Perl>
   PerlModule Para::Frame::Client

In .htaccess :

   AddHandler perl-script tt
   PerlHandler Para::Frame::Client
   ErrorDocument 404 /page_not_found.tt
   PerlSetVar port 7788

In some/public/file.tt :

   [% META title="Hello world" %]
   <p>This is a simple template</p>

=cut


sub startup
{
    my( $class ) = @_;

    # Site pages
    #
    unless( Para::Frame::Site->get('default') )
    {
	croak "No default site registred";
    }


    my $port = $CFG->{'port'};

    # Set up the tcp server. Must do this before chroot.
    $SERVER= IO::Socket::INET->new(
				   LocalPort => $port,
				   Proto    => 'tcp',
				   Listen  => 10,
				   Reuse  => 1,
				   )
	or (die "Cannot connect to socket $port: $@\n");

    warn "Connected to port $port\n";

    nonblock($SERVER);
    $SELECT = IO::Select->new($SERVER);

    # Setup signal handling
    $SIG{CHLD} = \&REAPER;

    Para::Frame->run_hook(undef, 'on_startup');

    warn "Setup complete, accepting connections\n";

    $LEVEL      = 0;
    $TERMINATE  = 0;
    $IN_STARTUP = 0;
}

=head2 watchdog_startup

  Para::Frame->watchdog_startup

Starts the L<Para::Frame::Watchdog>.

You may want to use L</daemonize> instead.

=cut

sub watchdog_startup
{
    Para::Frame::Watchdog->startup();
    Para::Frame::Watchdog->watch_loop();
}

sub main_loop
{
    my( $child, $timeout ) = @_;

    # Optional $timeout params used for convaying how much in a hurry
    # the yielding party is. Espacially, if it's waiting for something
    # and realy want to give that something some time

    if( $child )
    {
	$LEVEL ++;
    }

    $LAST = time; # To give ingo about if it's time to yield

    debug(4,"Entering main_loop at level $LEVEL",1) if $LEVEL;
    print "MAINLOOP $LEVEL\n" unless $Para::Frame::FORK;

    $timeout ||= $LEVEL ? TIMEOUT_SHORT : TIMEOUT_LONG;

    while (1)
    {
	# The algorithm was adopted from perlmoo by Joey Hess
	# <joey@kitenet.net>.

	my $exit_action = eval
	{

	    my $client;

	    foreach $client ($SELECT->can_read( $timeout ))
	    {
		if ($client == $SERVER)
		{
		    # Accept connection even if we should $TERMINATE since
		    # it could be communication for finishing existing
		    # requests

		    # New connection.
		    my($iaddr, $address, $port, $peer_host);
		    $client = $SERVER->accept;
		    if(!$client)
		    {
			debug(0,"Problem with accept(): $!");
			return;
		    }
		    ($port, $iaddr) = sockaddr_in(getpeername($client));
		    $peer_host = gethostbyaddr($iaddr, AF_INET)
		      || inet_ntoa($iaddr);
		    $SELECT->add($client);
		    nonblock($client);

		    debug(4,"\n\nNew client connected");
		}
		else
		{
		    switch_req(undef);
		    get_value( $client );
		}
	    }

	    ### Do the jobs piled up
	    #
	    $timeout = TIMEOUT_LONG; # We change this if there are jobs to do
	    # List may change during iteration by close_callback...
	    my @requests = values %REQUEST;
	    foreach my $req ( @requests )
	    {
		if( $req->{'in_yield'} )
		{
		    # Do not do jobs for a request that waits for a child
		    debug 5, "In_yield: $req->{reqnum}";
		}
		elsif( $req->{'cancel'} )
		{
		    debug "  cancelled by request";
		    $req->run_hook('done');
		    close_callback($req->{'client'});
		}
		elsif( $req->{'wait'} )
		{
		    # Waiting for something else to finish...
		    debug 4, "$req->{reqnum} stays open, was asked to wait for $req->{'wait'} things";
		}
		elsif( my $job = shift @{$req->{'jobs'}} )
		{
		    my( $cmd, @args ) = @$job;
		    switch_req( $req );
		    debug(2,"Found a job ($cmd) in $req->{reqnum}");
		    $req->$cmd( @args );
		}
		elsif( $req->{'childs'} )
		{
		    # Stay open while waiting for child
		    if( debug >= 4 )
		    {
			debug "$req->{reqnum} stays open, waiting for $req->{'childs'} childs";
			foreach my $child ( values %CHILD )
			{
			    my $creq = $child->req;
			    my $creqnum = $creq->{'reqnum'};
			    my $cclient = $creq->client;
			    my $cpid = $child->pid;
			    debug "  Req $creqnum $cclient has a child with pid $cpid";
			}
		    }
		}
		else
		{
		    # All jobs done for now
		    confess "req not a req ".Dumper $req unless ref $req eq 'Para::Frame::Request'; ### DEBUG
		    $req->run_hook('done');
		    close_callback($req->{'client'});
		}

		$timeout = TIMEOUT_SHORT; ### Get the jobs done quick
	    }

	    ### Do background jobs if no req jobs waiting
	    #
	    unless( values %REQUEST )
	    {
		add_background_jobs_conditional() and
		  $timeout = TIMEOUT_SHORT;
	    }


	    ### Waiting for a child? (*inside* a nested request)
	    #
	    if( $child )
	    {
		# This could be a simple yield and not a child, then just
		# exit now
		return "last" unless ref $child;

		# exit loop if child done
		return "last" unless $child->{'req'}{'childs'};
	    }
	    else
	    {
		if( $TERMINATE )
		{
		    # Exit asked to and nothing is in flux
		    if( not keys %REQUEST and
			not keys %CHILD   and
			not @BGJOBS_PENDING
		      )
		    {
			if( $TERMINATE eq 'HUP' )
			{
			    # Make watchdog restart us
			    debug "Executing HUP now";
			    exit 1;
			}
			elsif( $TERMINATE eq 'TERM' )
			{
			    # No restart
			    debug "Executing TERM now";
			    exit 0;
			}
			else
			{
			    debug "Termination code $TERMINATE not recognized";
			    $TERMINATE = 0;
			}
		    }
		}
	    }

	    ### Are there any data to be read from childs?
	    #
	    foreach my $child ( values %CHILD )
	    {
		my $child_data = ''; # We must init for each child!

		# Do a nonblocking read to get data. We try to read often
		# so that the buffer will not get full.

		$child->{'fh'}->read($child_data, POSIX::BUFSIZ);
		$child->{'data'} .= $child_data;

		if( $child_data )
		{
		    my $cpid = $child->pid;
		    my $length = length( $child_data );

		    my $tlength = length( $child->{'data'} );

		    if( $child->{'data'} =~ /^(\d{1,8})\0/ )
		    {
			# Expected length
			my $elength = length($1)+$1+2;
			if( $tlength == $elength )
			{
			    # Whole string recieved!
			    unless( $child->{'done'} ++ )
			    {
				# Avoid double deregister
				$child->deregister(undef,$1);
				delete $CHILD{$cpid};
				kill 9, $cpid;
			    }
			}
		    }
		    else
		    {
			debug "Got '$child->{data}'";
		    }
		}
	    }
        } || 'next'; #default
	if( $@ )
	{
	    my $err = run_error_hooks(catch($@));

	    warn "# FATAL REQUEST ERROR!!!\n";
	    warn "# Unexpected exception:\n";
	    warn "#>>\n";
	    warn map "#>> $_\n", split /\n/, $err->as_string;
	    warn "#>>\n";

	    my $emergency_level = Para::Frame::Watchdog::EMERGENCY_DEBUG_LEVEL;
	    if( $Para::Frame::DEBUG < $emergency_level )
	    {
		$Para::Frame::DEBUG =
		  $Para::Frame::Client::DEBUG =
		    $Para::Frame::CFG->{'debug'} =
		      $emergency_level;
		warn "#Raising global debug to level $Para::Frame::DEBUG\n";
	    }
	    else
	    {
		die $err;
	    }

	    $timeout = TIMEOUT_SHORT;
	}

	if( $exit_action eq 'last' )
	{
	    last;
	}
    }
    debug(4,"Exiting  main_loop at level $LEVEL",-1);
    $LEVEL --;
}


sub switch_req
{
    # $_[0] => the new $req
    # $_[1] => true if this is a new request

    no warnings 'uninitialized';

    if( $_[0] ne $REQ )
    {
	if( $REQ )
	{
	    # Detatch %ENV
	    $REQ->{'env'} = {%ENV};
	}

	Para::Frame->run_hook($REQ, 'before_switch_req');

	if( $_[0] and not $_[1] )
	{
	    if( $REQ )
	    {
		warn sprintf "\n$_[0]->{reqnum} Switching to req (from $REQ->{reqnum})\n", ;
	    }
	    elsif( $_[0] ne $REQ_LAST )
	    {
		warn sprintf "\n$_[0]->{reqnum} Switching to req\n", ;
	    }
	}

	$U = undef;
	if( $REQ = $_[0] )
	{
	    if( my $s = $REQ->{'s'} )
	    {
		$U   = $s->u;
		$DEBUG  = $s->{'debug'};
	    }

	    # Attach %ENV
	    %ENV = %{$REQ->{'env'}};
	    $REQ->{'env'} = \%ENV;

	    $INDENT = $REQ->{'indent'};

	    $REQ_LAST = $REQ; # To remember even then $REQ is undef
	}
	else
	{
	    undef %ENV;
	}
    }
}

sub get_value
{
    my( $client ) = @_;

    # Either we know we have something to read
    # or we are expecting an answer shortly

    if( $Para::Frame::FORK )
    {
	debug(2,"Getting value inside a fork");
	while( $_ = <$Para::Frame::Client::SOCK> )
	{
	    if( s/^([\w\-]{3,10})\0// )
	    {
		my $code = $1;
		debug(1,"Code $code");
		chomp;
		if( $code eq 'RESP' )
		{
		    my $val = $_;
		    debug(1,"RESP ($val)");
		    return $val;
		}
		else
		{
		    die "Unrecognized code: $code\n";
		}
	    }
	    else
	    {
		die "Unrecognized response: $_\n";
	    }
	}

	undef $Para::Frame::Client::SOCK;
	return;
    }


    if( ref $client eq 'Para::Frame::Request' )
    {
	my $req = $client;
	$client = $req->client;
	if( $client =~ /^background/ )
	{
	    if( my $areq = $req->{'active_reqest'} )
	    {
		debug 4, "  Getting value from active_request for $client";
		$client = $areq->client;
		debug 4, "    $client";
	    }
	    else
	    {
		die "We cant get a value without an active request ($client)\n";
		# Unless it's a fork... (handled above)
	    }
	}
    }

    if( debug >= 4 )
    {
	debug "Get value from $client";
	if( my $req = $REQUEST{$client} )
	{
	    my $reqnum = $req->{'reqnum'};
	    debug "  Req $reqnum";
	}
	else
	{
	    debug "  Not a Req (yet?)";
	}
    }
    

    my $time = time;
    my $timeout = 5;
  WAITE:
    while(1)
    {
	foreach my $ready ( $SELECT->can_read( $timeout ) )
	{
	    last WAITE if $ready == $client;
	}
	if( time > $time + $timeout )
	{
	    warn "Data timeout!!!";

	    if( my $req = $REQUEST{$client} )
	    {
		debug $req->debug_data;
	    }

	    cluck "trace for $client";
	    throw('action', "Data timeout while talking to client\n");
	}
    }

    # Read data from client.
    my $data='';
    my $rv = $client->recv($data,POSIX::BUFSIZ, 0);

    debug(4,"Read data...");

    unless (defined $rv && length $data)
    {
	# EOF from client.
	close_callback($client,'eof');
	debug(4,"End of file");
	return undef;
    }

    $INBUFFER{$client} .= $data;
    unless( $DATALENGTH{$client} )
    {
	debug(4,"Length of record?");
	# Read the length of the data string
	#
	if( $INBUFFER{$client} =~ s/^(\d+)\x00// )
	{
	    debug(4,"Setting length to $1");
	    $DATALENGTH{$client} = $1;
	}
	else
	{
	    die "Strange INBUFFER content: $INBUFFER{$client}\n";
	}
    }

    if( $DATALENGTH{$client} )
    {
	debug(4,"End of record?");
	# Have we read the full record of data?
	#
	if( length $INBUFFER{$client} >= $DATALENGTH{$client} )
	{
	    debug(4,"The whole length read");

	    if( $INBUFFER{$client} =~ s/^(\w+)\x00// )
	    {
		my( $code ) = $1;
		if( $code eq 'REQ' )
		{
		    my $record = $INBUFFER{$client};

		    # Clear BUFFER so that we can recieve more from
		    # same place.

		    $INBUFFER{$client} = '';
		    $DATALENGTH{$client} = 0;

		    handle_request( $client, \$record );
		}
		elsif( $code eq 'CANCEL' )
		{
		    debug(0,"CANCEL client");
		    my $req = $REQUEST{ $client };
		    unless( $req )
		    {
			debug "  Req not registred";
			return;
		    }
		    if( $req->{'childs'} )
		    {
			debug "  Killing req childs";
			foreach my $child ( values %CHILD )
			{
			    my $creq = $child->req;
			    my $cpid = $child->pid;
			    if( $creq->{'reqnum'} == $req->{'reqnum'} )
			    {
				kill 9, $child->pid;
			    }
			}
		    }
		    if( $req->{'in_yield'} )
		    {
			$req->{'cancel'} = 1;
			debug "  winding up yield";
		    }
		    else
		    {
			$DATALENGTH{$client} = 0;
			close_callback($client);
		    }
		}
		elsif( $code eq 'RESP' )
		{
		    my $val = $INBUFFER{$client};
		    debug(4,"RESP recieved ($val)");
		    $INBUFFER{$client} = '';
		    $DATALENGTH{$client} = 0;
		    return $val;
		}
		elsif( $code eq 'URI2FILE' )
		{
		    # redirect request from child to client (via this parent)
		    #
		    my $val = $INBUFFER{$client};
		    $val =~ s/^(.+?)\x00// or die "Faulty val: $val";
		    my $caller_clientaddr = $1;

		    debug(2,"URI2FILE($val) recieved");
#		    warn "  for $caller_clientaddr\n";
#		    warn "  from $client\n";

		    # Calling uri2file in the right $REQ
		    my $current_req = $REQ;
		    my $req = $REQUEST{ $caller_clientaddr } or
			die "Client $caller_clientaddr not registred";
		    my $file = $req->uri2file($val);

		    # Send response in calling $REQ
		    debug(2,"Returning answer $file");

		    $client->send(join "\0", 'RESP', $file );
		    $client->send("\n");
		}
		elsif( $code eq 'PING' )
		{
		    debug(4,"PING recieved");
		    $client->send("PONG\n");
		    debug(4,"Sent PONG as response");
		}
		elsif( $code eq 'MEMORY' )
		{
		    debug(2,"MEMORY recieved");
		    my $size = $INBUFFER{$client};
		    Para::Frame->run_hook(undef, 'on_memory', $size);
		}
		elsif( $code eq 'HUP' )
		{
		    debug(0,"HUP recieved");
		    $TERMINATE = 'HUP';
		}
		elsif( $code eq 'TERM' )
		{
		    debug(0,"TERM recieved");
		    $TERMINATE = 'TERM';
		}
		else
		{
		    debug(0,"Strange CODE: $code");
		}
	    }
	    else
	    {
		debug(0,"No code given: $INBUFFER{$client}");
	    }

	    $INBUFFER{$client} = '';
	    $DATALENGTH{$client} = 0;
	}
    }
}

sub nonblock
{
    my $socket=shift;

    # Set a socket into nonblocking mode.  I guess that the 1.18
    # defaulting to autoflush makes this function redundant

    use Fcntl;
    my $flags= fcntl($socket, F_GETFL, 0) 
	or die "Can't get flags for socket: $!\n";
    fcntl($socket, F_SETFL, $flags | O_NONBLOCK)
	or die "Can't make socket nonblocking: $!\n";
}

sub close_callback
{
    my( $client, $reason ) = @_;

    # Someone disconnected or we want to close the i/o channel.

    if( $reason )
    {
#	debug(4,"Done $client $REQUEST{$client}{'reqnum'} ($reason)");
	debug(4, "Done ($reason)");
    }
    else
    {
#	warn "Done $client $REQUEST{$client}{'reqnum'}\n";
	warn "$REQUEST{$client}{reqnum} Done\n";
    }

    if( $client =~ /^background/ )
    {
	#(May be a subrequst, but decoupled)

	# Releasing active request
	delete $REQUEST{$client}{'active_reqest'};
	delete $REQUEST{$client};
	switch_req(undef);
    }
    elsif( $REQUEST{$client}{'original_request'} )
    {
	# This is a subrequest

	# It's done now. But we must wait on the root request to
	# finish also. They both uses the same client. Thus, don't
	# touch the client.

	# But it may be that the parent already is done. (See
	# Para::Frame::Request->new_subrequest) )

#	$::SRCNT++;
#	debug "This was subrequest ending $::SRCNT";
#	exit if $::SRCNT >= 10;

	return;
    }
    else
    {
	delete $REQUEST{$client};
	delete $INBUFFER{$client};
	switch_req(undef);
	$SELECT->remove($client);
	close($client);
    }
}

sub REAPER
{
    # Taken from example in perl doc

    my $child_pid;
    # If a second child dies while in the signal handler caused by the
    # first death, we won't get another signal. So must loop here else
    # we will leave the unreaped child as a zombie. And the next time
    # two children die we get another zombie. And so on.

    warn "| In reaper\n" if $DEBUG > 1;

    while (($child_pid = waitpid(-1, POSIX::WNOHANG)) > 0)
    {
	warn "| Child $child_pid exited with status $?\n";

	if( my $child = delete $CHILD{$child_pid} )
	{
	    $child->deregister( $? )
		unless $child->{'done'};
	}
	else
	{
	    warn "|   No object registerd with PID $child_pid\n";
#	    warn "|     This may be a child already handled\n";
#	    warn "|     Or some third party thing like Date::Manip...\n";
	}
    }
    $SIG{CHLD} = \&REAPER;  # still loathe sysV
}

=head2 daemonize

  Para::Frame->daemonize( $run_watchdog )

Starts the paraframe daemon in the background. If C<$run_watchdog> is
true, lets L<Para::Frame::Watchdog> start and watch over the daemon.

=cut

sub daemonize
{
    my( $class, $run_watchdog ) = @_;

    # Detatch AFTER watchdog started sucessfully

    my $parent_pid = $$;

    $SIG{CHLD} = sub
    {
	warn "Error during daemonize\n";
	exit 1;
    };
    $SIG{USR1} = sub
    {
	warn "Running in background\n" if $DEBUG > 3;
	exit 0;
    };

    chdir '/'                 or die "Can't chdir to /: $!";
    defined(my $pid = fork)   or die "Can't fork: $!";
    if( $pid ) # In parent
    {
#	open STDIN, '/dev/null'   or die "Can't read /dev/null: $!";
#	open STDOUT, '>/dev/null' or die "Can't write to /dev/null: $!";
	while(1)
	{
	    # Waiting for signal from child
	    sleep 2;
	    warn "---- Waiting for ready signal\n" if $DEBUG > 1;
	}
	exit;
    }

    # Reset signal handlers for the child
    $SIG{CHLD} = 'DEFAULT';
    $SIG{USR1} = 'DEFAULT';

    if( $run_watchdog )
    {
	Para::Frame::Watchdog->startup(1);
	open_logfile();
	POSIX::setsid             or die "Can't start a new session: $!";
	write_pidfile();
	kill 'USR1', $parent_pid; # Signal parent
	Para::Frame::Watchdog->watch_loop();
    }
    else
    {
	warn "\n\nStarted process $$ on ".now()."\n\n";
	Para::Frame->startup();
	open_logfile();
	POSIX::setsid             or die "Can't start a new session: $!";
	write_pidfile();
	kill 'USR1', $parent_pid; # Signal parent
	warn "\n\nStarted process $$ on ".now()."\n\n";
	Para::Frame::main_loop();
    }
}


sub add_background_jobs_conditional
{

    # Add background jobs to do unless the load is too high, uless we
    # waited too long anyway
    return if $TERMINATE;

    # Return it hasn't passed BGJOB_MAX secs since last time
    my $last_time = $BGJOBDATE ||= time;
    my $delta = time - $last_time;

    return if $delta < BGJOB_MAX;

    # Cache cleanup could safely be done here
    # But nothing that requires a $req
    Para::Frame->run_hook(undef, 'busy_background_job', $delta);


    return unless $CFG->{'do_bgjob'};


    # Return if CPU load is over BGJOB_CPU
    my $sysload;
    if( $delta < BGJOB_MIN ) # unless a long time has passed
    {
	$sysload = (Sys::CpuLoad::load)[1];
	return if $sysload > BGJOB_CPU;
    }

    # Return if we had no visitors unless BGJOB_MED secs passed
    $BGJOBNR ||= -1;
    if( $BGJOBNR == $REQNUM )
    {
	return if $delta < BGJOB_MED;
    }

    ### Reload updated modules
    Para::Frame::Reload->check_for_updates;

    add_background_jobs($delta, $sysload);
}

sub add_background_jobs
{
    my( $delta, $sysload ) = @_;

    $REQNUM ++;
    my $client = "background-$REQNUM";
    my $req = Para::Frame::Request->new_minimal($REQNUM, $client);

    ### Register the request
    $REQUEST{$client} = $req;
    switch_req( $req, 1 );

    warn "\n\n$REQNUM Handling new request (in background)\n";

    my $bg_user;
    my $user_class = $Para::Frame::CFG->{'user_class'};

    # Make sure the user is the same for all jobs in a request

    # Add pending jobs set up with $req->add_background_job
    #
    if( @BGJOBS_PENDING )
    {
	my $job = shift @BGJOBS_PENDING;
	my $original_request = shift @$job;
	my $reqnum = $original_request->{'reqnum'};
	$bg_user = $original_request->session->u;
	$user_class->change_current_user($bg_user);

	# Make sure the original request is the same for all jobs in
	# each background request

	$req->{'original_request'} = $original_request;
	$req->{'page'} = Para::Frame::Page->new();
	$req->{'page'}->set_site($original_request->site);
	$req->add_job('run_code', @$job);

	for( my $i=0; $i<=$#BGJOBS_PENDING; $i++ )
	{
	    if( $BGJOBS_PENDING[$i][0]{'reqnum'} == $reqnum )
	    {
		my $job = splice @BGJOBS_PENDING, $i, 1;
		shift @$job;
		$req->add_job('run_code', @$job);

		# This may have been the last item in the list
		$i--;
	    }
	}
    }
    elsif( not $TERMINATE )
    {
	$bg_user = &{ $Para::Frame::CFG->{'bg_user_code'} };
	$user_class->change_current_user($bg_user);

	### Debug info
	if( debug > 2 )
	{
	    my $t = now();
	    my $s = $req->s;
	    warn sprintf("# %s %s - localhost\n# Sid %s - Uid %d - debug %d\n",
			 $t->ymd,
			 $t->hms('.'),
			 $s->id,
			 $s->u->id,
			 $s->{'debug'},
			 );
	}

	Para::Frame->run_hook($req, 'add_background_jobs', $delta, $sysload);
    }

    $BGJOBDATE = time;
    $BGJOBNR   = $REQNUM;
}

##############################################
# Handle the request
#
sub handle_request
{
    my( $client, $recordref ) = @_;

    $REQNUM ++;
    warn "\n\n$REQNUM Handling new request\n";

    ### Reload updated modules
    Para::Frame::Reload->check_for_updates;

    ### Create request ($REQ not yet set)
    my $req = new Para::Frame::Request( $REQNUM, $client, $recordref );
    ### Register the request
    $REQUEST{ $client } = $req;
    switch_req( $req, 1 );

    $req->init;

    # Authenticate user identity
    my $user_class = $Para::Frame::CFG->{'user_class'};
    $user_class->identify_user;     # Will set $s->{user}
    $user_class->authenticate_user;

    ### Debug info
    my $t = now();
    my $s = $req->s;
    warn sprintf("# %s %s - %s\n# Sid %s - Uid %d - debug %d\n",
		 $t->ymd,
		 $t->hms('.'),
		 $req->client_ip,
		 $s->id,
		 $s->u->id,
		 $s->{'debug'},
		 );
    warn "# $client\n" if debug() > 4;

    ### Redirected from another page?
    if( my $page_result = $req->s->{'page_result'}{ $req->uri } )
    {
	$req->page->set_headers( $page_result->[0] );
	$req->page->send_headers;
	$req->client->send( ${$page_result->[1]} );
	delete $req->s->{'page_result'}{ $req->uri };
    }
    else
    {
	$req->setup_jobs;
	$req->after_jobs;
    }

    ### Clean up used globals
}

=head2 add_hook

  Para::Frame->add_hook( $label, \&code )

Adds code to be run on special occations

Availible hooks are:

=head3 on_startup

Runs just before the C<main_loop>.

=head3 on_memory

Runs then the watchdog send a C<MEMORY> notice.

=head3 on_error_detect

Runs then the exception is catched by
L<Para::Frame::Result/exception>.

=head3 on_fork

Runs in the child just after the fork.

=head3 done

Runs just before the request is done.

=head3 user_login

Runs after user logged in, in L<Para::Frame::Action::user_login>

=head3 before_user_logout

Runs after user logged out, in L<Para::Frame::User/logout>

=head3 after_db_connect

Runs after each DB connect from L<Para::Frame::DBIx/connect>

=head3 before_db_commit

Runs before committing each DB, from L<Para::Frame::DBIx/commit>

=head3 after_db_rollback

Runs after a rollback för each DB, from L<Para::Frame::DBIx/rollback>

=head3 before_switch_req

Runs just before switching from one request to another. Not Switching
from one request to another can be done several times before the
request is done.

=head3 before_render_output

Runs before the result page starts to render.

=head3 busy_background_job

Runs often, between requests.

=head3 add_background_jobs

For adding jobs that should be done in the background, then there is
nothing else to do or then it hasen't run in a while.

=cut

sub add_hook
{
    my( $class, $label, $code ) = @_;

    debug(4,"add_hook $label from ".(caller));

    # Validate hook label
    unless( $label =~ /^( on_startup          |
			  on_memory           |
			  on_error_detect     |
			  on_fork             |
			  done                |
			  user_login          |
			  before_user_logout  |
			  after_user_logout   | # not used
			  after_db_connect    |
			  before_db_commit    |
			  after_db_rollback   |
			  before_switch_req   |
			  before_render_output|
			  busy_background_job |
			  add_background_jobs
			  )$/x )
    {
	die "No such hook: $label\n";
    }

    $HOOK{$label} ||= [];
    push @{$HOOK{$label}}, $code;
}

sub run_hook
{
    my( $class, $req, $label ) = (shift, shift, shift);
    if( debug > 3 )
    {
	unless( $label )
	{
	    carp "Hook label missing";
	}

	if( $req and $req->{reqnum} )
	{
	    debug(0,"run_hook $label for $req->{reqnum}");
	}
	else
	{
	    debug(0,"run_hook $label");
	}
#    warn Dumper($hook, \@_);
    }

    return unless $HOOK{$label};

    my %running = (); # Stop on recursive running

    my $hooks = $HOOK{$label};
    $hooks = [$hooks] unless ref $hooks eq 'ARRAY';
    foreach my $hook (@$hooks)
    {
	if( $Para::Frame::hooks_running{"$hook"} )
	{
	    warn "Avoided running $label hook $hook again\n";
	}
	else
	{
	    $Para::Frame::hooks_running{"$hook"} ++;
	    switch_req( $req ) if $req;
#	    warn "about to run coderef $hook with params @_"; ## DEBUG
	    eval
	    {
		&{$hook}(@_);
	    };
	    $Para::Frame::hooks_running{"$hook"} --;
	    if( $@ )
	    {
		debug(2, "hook $label throw an exception".Dumper($@));
		die $@;
	    }
	}
    }
    return 1;
}

=head2 add_global_tt_params

  Para::Frame->add_global_tt_params( \%params )

Adds all params to the global params to be used for all
templates. Replacing existing params if the name is the same.

=cut

sub add_global_tt_params
{
    my( $class, $params ) = @_;

    while( my($key, $val) = each %$params )
    {
	$PARAMS->{$key} = $val;
#	cluck("Add global TT param $key from ");
    }
}

sub write_pidfile
{
    my( $pid ) = @_;
    $pid ||= $$;
    my $pidfile = $Para::Frame::CFG->{'pidfile'};
#    warn "Writing pidfile: $pidfile\n";
    create_file( $pidfile, "$pid\n",
		 {
		     do_not_chmod_dir => 1,
		 });
    $ACTIVE_PIDFILE = $pid;
}

sub remove_pidfile
{
    my $pidfile = $Para::Frame::CFG->{'pidfile'};
    unlink $pidfile or warn "Failed to remove $pidfile: $!\n";
}

END
{
    if( $ACTIVE_PIDFILE and $ACTIVE_PIDFILE == $$ )
    {
	remove_pidfile();
	undef $ACTIVE_PIDFILE;
    }
}


sub open_logfile
{
    my $log = $CFG->{'logfile'};

    open STDOUT, '>>', $log   or die "Can't append to $log: $!";
    open STDERR, '>&STDOUT'   or die "Can't dup stdout: $!";

    chmod_file($log);
}


#######################################################################

=head2 configure

  Para::Frame->configure( \%cfg )

Configures paraframe before startup. The configuration is stored in
C<$Para::Frame::CFG>

These configuration params are used:

=head3 debug

Sets global C<$Para::Frame::DEBUG> value that will be used as default
debug value for all sessions. Also sets debug value for the
C<Para::Frame::Client> then used from the server.

Default is 0.

=head3 dir_var

The base for L</dir_log> and L</dir_run>.

Default is C</var>

=head3 dir_log

The dir to store the paraframe log.

Default is C<$dir_var/log>

=head3 dir_run

The dir to store the process pid.

Default is C<$dir_var/run>

=head3 paraframe

The dir that holds paraframe.

Default is C</usr/local/paraframe>

=head3 paraframe_group

The file group to set files to that are created.

Default is C<staff>

=head3 approot

The path to application. This is the dir that holds the C<lib> and
possibly the C<var> dirs. See L<Para::Frame::Site/approot>.

Must be defined

=head3 appback

This is a listref of server paths. Each path should bee a dir that
holds a C<html> dir, or a C<dev> dir, for compiled sites.  See
L<Para::Frame::Site/appback>.

Must be defined

=head3 time_zone

Sets the time zone for L<Para::Frame::Time>.

Defaults to C<local>

=head3 time_format

Sets the default presentation of times using
L<Para::Frame::Time/format_datetime>

Defaults to C<%Y-%m-%d %H.%M>

=head3 umask

The default umask for created files.

Defaults C<0007>

=head3 appfmly

This should be a listref of elements, each to be treated ass fallbacks
for L</appbase>.  If no actions are found under L</appbase> one after
one of the elements in C<appfmly> are tried. See
L<Para::Frame::Site/appfmly>.

Defaults to none.

=head3 ttcdir

The directory that holds the compiled templates.

Defaults to L</appback> or L</approot> followed by C</var/ttc>.

=head3 tt_plugins

Adds a list of L<Template::Plugin> bases. Always adds
L<Para::Frame::Template::Plugin>.

Defaults to the empty list.

=head3 port

The port top listen on for incoming requests.

Defaults to C<7788>.

=head3 pidfile

The file to use for storing the paraframe pid.

Defaults to L</dir_run> followed by C</parframe_$port.pid>

=head3 logfile

The file to use for logging.

Defaults to L</dir_run> followed by C</parframe_$port.log>

=head3 user_class

The class to use for user identification. Should be a subclass to
L<Para::Frame::User>.

Defaults to C<Para::Frame::User>

=head3 session_class

The class to use for sessopms- Should be a subclass to
L<Para::Frame::Session>.

Defaults to C<Para::Frame::Session>

=head3 bg_user_code

A coderef that generates a user object to be used for background jobs.

Defaults to code that C<get> C<guest> fråm L</user_class>.

=head3 th

C<th> is a ref to a hash of L<Para::Frame::Burner> objects. You should
use the default configuration.

There are three standard burners.

  html     = The burner used for all tt pages

  plain    = The burner used for emails and other plain text things

  html_pre = The burner for precompiling of tt pages

Example for adding a filter to the html burner:

  $Para::Frame::CFG->{'th'}{'html'}->add_filters({
      'upper_case' => sub{ return uc($_[0]) },
  });

See also L<Para::Frame::Burner>

=cut

sub configure
{
    my( $class, $cfg_in ) = @_;

    $cfg_in or die "No configuration given\n";

    # Init global variables
    #
    $REQNUM     = 0;
    $CFG        = {};
    $PARAMS     = {};
    $INDENT     = 0;

    $ENV{PATH} = "/usr/bin:/bin";

    # Init locale
    setlocale(LC_ALL, "sv_SE");
    setlocale(LC_NUMERIC, "C");

    $CFG = $cfg_in; # Assign to global var

    ### Set main debug level
    $DEBUG = $CFG->{'debug'} || 0;
    $Para::Frame::Client::DEBUG = $DEBUG;

    $CFG->{'dir_var'} ||= '/var';
    $CFG->{'dir_log'} ||= $CFG->{'dir_var'}."/log";
    $CFG->{'dir_run'} ||= $CFG->{'dir_var'}."/run";

    $CFG->{'paraframe'} ||= '/usr/local/paraframe';

    $CFG->{'paraframe_group'} ||= 'staff';
    getgrnam( $CFG->{'paraframe_group'} )
	or die "paraframe_group $CFG->{paraframe_group} doesn't exist\n";

    $CFG->{'approot'} || $CFG->{'appback'}
      or die "appback or approot missing in config\n";

    # $Para::Frame::Time::TZ is set at startup from:
    #
    $CFG->{'time_zone'} ||= "local";
    $Para::Frame::Time::TZ =
	DateTime::TimeZone->new( name => $CFG->{'time_zone'} );

    $CFG->{'time_format'} ||= "%Y-%m-%d %H.%M";
    $Para::Frame::Time::FORMAT = $CFG->{'time_format'};

    $CFG->{'umask'} ||= 0007;
    umask($CFG->{'umask'});


    # Make appfmly and appback listrefs if they are not
    foreach my $key ('appfmly', 'appback')
    {
	unless( ref $CFG->{$key} )
	{
	    my @content = $CFG->{$key} ? $CFG->{$key} : ();
	    $CFG->{$key} = [ @content ];
	}

	if( $DEBUG > 3 )
	{
	    warn "$key set to ".Dumper($CFG->{$key});
	}
    }

    my $ttcbase = $CFG->{'appback'}[0] || $CFG->{'approot'};
    $CFG->{'ttcdir'} ||= $ttcbase . "/var/ttc";

    my $tt_plugins = $CFG->{'tt_plugins'} || [];
    $tt_plugins = [$tt_plugins] unless ref $tt_plugins;
    push @$tt_plugins, 'Para::Frame::Template::Plugin';


    my %th_default =
	(
	 PRE_PROCESS => 'header_prepare.tt',
	 POST_PROCESS => 'footer.tt',
	 TRIM => 1,
	 PRE_CHOMP => 1,
	 POST_CHOMP => 1,
	 RECURSION => 1,
	 PLUGIN_BASE => $tt_plugins,
	 ABSOLUTE => 1,
	 );

    $CFG->{'th'}{'html'} ||= Para::Frame::Burner->new({
	%th_default,
	INTERPOLATE => 1,
	COMPILE_DIR =>  $CFG->{'ttcdir'}.'/html',
        type => 'html',
	subdir_suffix => '',
    });

    $CFG->{'th'}{'html_pre'} ||= Para::Frame::Burner->new({
	%th_default,
	COMPILE_DIR =>  $CFG->{'ttcdir'}.'/html_pre',
	TAG_STYLE => 'star',
        type => 'html_pre',
	subdir_suffix => '_pre',
    });

    $CFG->{'th'}{'plain'} ||= Para::Frame::Burner->new({
	INTERPOLATE => 1,
	COMPILE_DIR => $CFG->{'ttcdir'}.'/plain',
	FILTERS =>
	{
	    'uri' => sub { CGI::escape($_[0]) },
	    'lf'  => sub { $_[0] =~ s/\r\n/\n/g; $_[0] },
	    'autoformat' => sub { autoformat($_[0]) },
	},
        type => 'plain',
	subdir_suffix => '_plain',
    });

    $CFG->{'port'} ||= 7788;

    $CFG->{'pidfile'} ||= $CFG->{'dir_run'} .
	"/parframe_" . $CFG->{'port'} . ".pid";
    $CFG->{'logfile'} ||= $CFG->{'dir_log'} .
	"/paraframe_" . $CFG->{'port'} . ".log";

    $CFG->{'user_class'} ||= 'Para::Frame::User';
    $CFG->{'session_class'} ||= 'Para::Frame::Session';

    $CFG->{'bg_user_code'} ||= sub{ $CFG->{'user_class'}->get('guest') };

    $class->set_global_tt_params;

    # Configure other classes
    #
    Para::Frame::Route->on_configure;
    Para::Frame::Widget->on_configure;
    Para::Frame::Email::Address->on_configure;

    # Making the version availible
    $CFG->{'version'} = $VERSION;
}

=head2 Session

  Para::Frame->Session

Returns the L</session_class> string.

=cut

sub Session
{
    $CFG->{'session_class'};
}

=head3 User

  Para::Frame->User

Returns the L</user_class> string.

=cut

sub User
{
    $CFG->{'user_class'};
}

=head3 dir

Returns the L</paraframe> dir.


=cut

sub dir
{
    return $CFG->{'paraframe'};
}



#######################################################################

=head2 set_global_tt_params

The standard functions availible in templates.

Most of them exists in both from client and not client.

=over

=item cfg

$app->conf : L<Para::Frame/configure>

=item debug

Emit a debug message in the error log. See L<Para::Frame::Utils/debug>

=item dump

The L<Data::Dumper/Functions> Dumper().  To be used for
debugging. Either dump the data structure inside the page (in
<pre></pre>) or combine with debug to send the dump to the error
log. For example: [% debug(dump(myvar)) %]

=item emergency_mode

True if paraframe recovered from an abnormal error.

=item rand

Produce a random integer number, at least 0 and at most one less than
the number given as param.

=item timediff

See L<Para::Frame::Utils/timediff>

=item uri

See L<Para::Frame::Utils/uri>

=item uri_path

See L<Para::Frame::Utils/uri_path>

=item warn

Emit a warning in the error log, excluding the linenumber
(L<perlfunc/warn>). You should use debug() instead.

=back

See also L<Para::Frame::Widget>

=cut

sub set_global_tt_params
{
    my( $class ) = @_;

    my $params =
    {
	'cfg'             => $Para::Frame::CFG,
	'dump'            => \&Dumper,
	'warn'            => sub{ warn($_[0],"\n");"" },
	'debug'           => sub{ debug(@_) },
	'emergency_mode'  => sub{ $Para::Frame::Watchdog::EMERGENCY_MODE },
	'rand'            => sub{ int rand($_[0]) },
	'uri'             => \&Para::Frame::Utils::uri,
	'uri_path'        => \&Para::Frame::Utils::uri_path,
        'timediff'        => \&Para::Frame::Utils::timediff,
    };

    $class->add_global_tt_params( $params );
}

1;

#########################################################


=head1 AUTHOR

Jonas Liljegren E<lt>jonas@paranormal.seE<gt>

=head1 SEE ALSO

L<Template>

=cut

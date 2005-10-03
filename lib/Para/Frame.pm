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

BEGIN
{
    our $CVSVERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    our $VERSION = "1.00"; # Paraframe version
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Watchdog;
use Para::Frame::Request;
use Para::Frame::Widget;
use Para::Frame::Burner;
use Para::Frame::Time qw( now );
use Para::Frame::Utils qw( throw uri2file debug create_file chmod_file fqdn );

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
our $REAPER_FAILSAFE;      # Testing...

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

    debug(4,"Entering main_loop at level $LEVEL",1) if $LEVEL;
    print "MAINLOOP $LEVEL\n";

    $timeout ||= $LEVEL ? TIMEOUT_SHORT : TIMEOUT_LONG;

    while (1)
    {
	# The algorithm was adopted from perlmoo by Joey Hess
	# <joey@kitenet.net>.

	# I could also use IO::Multiplex or Net::Server::Multiplex or POE



#	    warn "...\n";
	#    my $t0 = [gettimeofday];

	my $client;

	# See if clients have sent any data.
	#    my @client_list = $select->can_read(1);
	#    print "T 1: ", tv_interval ( $t0, [gettimeofday]), "\n";

	foreach $client ($SELECT->can_read( $timeout ))
	{
#	    warn "  Handle client $client\n";
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
		    next;
		}
		($port, $iaddr) = sockaddr_in(getpeername($client));
		$peer_host = gethostbyaddr($iaddr, AF_INET) || inet_ntoa($iaddr);
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
		debug 6, "In_yield: $req->{reqnum}";
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
#		if( $REAPER_FAILSAFE )
#		{
#		    debug "FAILSAFE REAPING";
#		    &REAPER if $REAPER_FAILSAFE > time;
#		    $REAPER_FAILSAFE = 0;
#		}
#		else
#		{
#		    $REAPER_FAILSAFE = time + 3;
#		}

		# Stay open while waiting for child
		if( debug >= 4 )
#		if(1)
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
	    last unless ref $child;

	    # exit loop if child done
	    last unless $child->{'req'}{'childs'};

#	    ### DEBUG
#	    warn "Waiting for a child\n";
#	    my $childs = $child->req->{'childs'};
#	    warn "  childs: $childs\n";
#		if( $REAPER_FAILSAFE )
#		{
#		    debug "FAILSAFE REAPING";
#		    &REAPER if $REAPER_FAILSAFE > time;
#		    $REAPER_FAILSAFE = 0;
#		}
#		else
#		{
#		    $REAPER_FAILSAFE = time + 3;
#		}
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

#	    warn sprintf "--> Checking $child, reading %d bytes\n", POSIX::BUFSIZ;

	    # Do a nonblocking read to get data. We try to read often
	    # so that the buffer will not get full.

	    $child->{'fh'}->read($child_data, POSIX::BUFSIZ);
	    $child->{'data'} .= $child_data;

	    if( $child_data )
	    {
		my $cpid = $child->pid;
		my $length = length( $child_data );
#		debug "Read $length bytes from $cpid";

		my $tlength = length( $child->{'data'} );
#		debug "  Total of $tlength bytes read";

		if( $child->{'data'} =~ /^(\d{1,5})\0/ )
		{
		    # Expected length
		    my $elength = length($1)+$1+2;
#		    debug "  Expecting $elength bytes";
		    if( $tlength == $elength )
		    {
			# Whole string recieved!
#			debug "  All data retrieved";
			unless( $child->{'done'} ++ )
			{
			    # Avoid double deregister
			    $child->deregister(undef,$1);
			    delete $CHILD{$cpid};
#			    debug "  Killing $cpid";
			    kill 9, $cpid;
			}
		    }
		}
		else
		{
		    debug "Got '$child->{data}'";
		}

	    }

#	    &REAPER; # In case we missed something...
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

#    warn "Waiting for client\n";
    if( debug >= 3 )
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
#	    warn "  Client ready\n";
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
		    switch_req( $req );
		    my $file =  uri2file($val);
		    switch_req( $current_req ) if $current_req;

		    # Send response in calling $REQ
		    debug(2,"Returning answer $file");
#		    debug "  to $client";



#		    $client->send(join "\0", 'URI2FILE', $file );
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
	# Releasing active request
	delete $REQUEST{$client}{'active_reqest'};
	delete $REQUEST{$client};
	switch_req(undef);
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

    warn "| In reaper\n";

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
	    warn "|     This may be a child already handled\n";
	    warn "|     Or some third party thing like Date::Manip...\n";
	}
    }
    $SIG{CHLD} = \&REAPER;  # still loathe sysV
}

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
	$sysload = Sys::CpuLoad::load;
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
    warn "\n\n$REQNUM Handling new request (in background)\n";
    my $client = "background-$REQNUM";
    my $req = Para::Frame::Request->new_minimal($REQNUM, $client);

    ### Register the request
    $REQUEST{$client} = $req;
    switch_req( $req, 1 );

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
	$bg_user = $original_request->s->u;
	$user_class->change_current_user($bg_user);

	# Make sure the original request is the same for all jobs in
	# each background request

	$req->{'original_request'} = $original_request;
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
 
    ### Further initialization that requires $REQ
    $req->ctype( $req->{'orig_ctype'} );
    $req->{'uri'} = $req->set_uri( $req->{'orig_uri'} );
    $req->{'s'}->route->init;

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
    warn "# $client\n" if debug();
   
    ### Redirected from another page?
    if( my $page_result = $req->s->{'page_result'}{ $req->uri } )
    {
	$req->{'headers'} = $page_result->[0];
	$req->send_headers;
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
			  after_user_logout   |
			  after_db_connect    |
			  before_db_commit    |
			  after_db_rollback   |
			  before_switch_req   |
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

	if( $req )
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
	    die $@ if $@;
	}
    }
    return 1;
}

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

    $CFG->{'approot'} or die "approot missing in config\n";
    $CFG->{'ttcdir'} ||= $CFG->{'approot'} . "/var/ttc";

    # $Para::Frame::Time::TZ is set at startup from:
    #
    $CFG->{'time_zone'} ||= "local";
    $Para::Frame::Time::TZ =
	DateTime::TimeZone->new( name => $CFG->{'time_zone'} );

    $CFG->{'umask'} ||= 0007;
    umask($CFG->{'umask'});


    # Site pages
    #
    unless( Para::Frame::Site->get('default') )
    {
	croak "No default site registred";
    }


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

    my %th_default =
	(
	 INCLUDE_PATH => [ \&Para::Frame::Burner::incpath_generator ],
	 PRE_PROCESS => 'header_prepare.tt',
	 POST_PROCESS => 'footer.tt',
	 TRIM => 1,
	 PRE_CHOMP => 1,
	 POST_CHOMP => 1,
	 RECURSION => 1,
	 PLUGIN_BASE => 'Para::Frame::Template::Plugin',
	 ABSOLUTE => 1,
	 );

    $CFG->{'th'}{'html'} ||= Para::Frame::Burner->new({
	%th_default,
	INTERPOLATE => 1,
	COMPILE_DIR =>  $CFG->{'ttcdir'}.'/html',
    });

    $CFG->{'th'}{'html_pre'} ||= Para::Frame::Burner->new({
	%th_default,
	COMPILE_DIR =>  $CFG->{'ttcdir'}.'/html_pre',
	TAG_STYLE => 'star',
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
    });

    $CFG->{'port'} ||= 7788;

    $CFG->{'pidfile'} ||= $CFG->{'dir_run'} .
	"/parframe_" . $CFG->{'port'} . ".pid";
    $CFG->{'logfile'} ||= $CFG->{'dir_log'} .
	"/paraframe_" . $CFG->{'port'} . ".log";

    $CFG->{'user_class'} ||= 'Para::Frame::User';

    $CFG->{'bg_user_code'} ||= sub{ $CFG->{'user_class'}->get('guest') };

    $class->set_global_tt_params;

    # Configure other classes
    #
    Para::Frame::Route->on_configure;
    Para::Frame::Widget->on_configure;
}

sub set_global_tt_params
{
    my( $class ) = @_;

    my $params =
    {
	'cfg'             => $Para::Frame::CFG,
	'dump'            => \&Dumper,
	'warn'            => sub{ warn($_[0],"\n");"" },
	'debug'           => sub{ debug(@_) },
	'rand'            => sub{ int rand($_[0]) },
	'uri'             => \&Para::Frame::Utils::uri,

	'selectorder'     => \&Para::Frame::Widget::selectorder,
	'slider'          => \&Para::Frame::Widget::slider,
	'jump'            => \&Para::Frame::Widget::jump,
	'submit'          => \&Para::Frame::Widget::submit,
	'go'              => \&Para::Frame::Widget::go,
	'go_js'           => \&Para::Frame::Widget::go_js,
	'forward'         => \&Para::Frame::Widget::forward,
	'forward_url'     => \&Para::Frame::Widget::forward_url,
	'alfanum_bar'     => \&Para::Frame::Widget::alfanum_bar,
	'rowlist'         => \&Para::Frame::Widget::rowlist,
	'list2block'      => \&Para::Frame::Widget::list2block,
	'preserve_data'   => \&Para::Frame::Widget::preserve_data,
	'param_includes'  => \&Para::Frame::Widget::param_includes,
	'hidden'          => \&Para::Frame::Widget::hidden,
	'input'           => \&Para::Frame::Widget::input,
	'textarea'        => \&Para::Frame::Widget::textarea,
	'filefield'       => \&Para::Frame::Widget::filefield,
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

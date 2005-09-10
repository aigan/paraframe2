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

use 5.006;
use strict;
use IO::Socket 1.18;
use IO::Select;
use Socket;
use POSIX;
use Text::Autoformat; #exports autoformat()
use Time::HiRes qw( time );
use Data::Dumper;
use Carp qw( cluck confess carp );
use Template;
use Sys::CpuLoad;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "  Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Watchdog;
use Para::Frame::Request;
use Para::Frame::Widget;
use Para::Frame::Time;
use Para::Frame::Utils qw( throw uri2file debug create_file chmod_file );

use constant TIMEOUT_LONG  =>   5;
use constant TIMEOUT_SHORT =>   0.001;
use constant BGJOB_MAX     =>   3;      # At most
use constant BGJOB_MED     =>  60 *  5; # Even if no visitors
use constant BGJOB_MIN     =>  60 * 15; # At least this often
use constant BGJOB_CPU     =>   0.5;

# Do not init variables here, since this will be redone each time code is updated
our $SERVER     ;
our $DEBUG      ;
our $INDENT     ;
our @JOBS       ;
our %REQUEST    ;
our $REQ        ;
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
our $TERMINATE  ;
our $IN_STARTUP;           # True until we reach the watchdog loop
our $ACTIVE_PIDFILE;       # The PID indicated by existing pidfile

# STDOUT goes to the watchdog. Use well defined messages!
# STDERR goes to the log

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

		debug(4,"\n\nNew client connected\n");
	    }
	    else
	    {
		$REQ = undef;
		get_value( $client );
	    }
	}

	### Do the jobs piled up
	#
	$timeout = TIMEOUT_LONG; # We change this if there are jobs to do
	foreach my $req ( values %REQUEST )
	{
#	    my $s = $req->s; ### DEBUG
#	    warn "Look for jobs for session $s\n"; ### DEBUG

	    if( $req->{'in_yield'} )
	    {
		# Do not do jobs for a request that waits for a child
	    }
	    elsif( my $job = shift @{$req->{'jobs'}} )
	    {
		my( $cmd, @args ) = @$job;
		debug(2,"Found a job ($cmd) in $req->{reqnum}");
		switch_req( $req );
		$req->$cmd( @args );
	    }
	    elsif( $req->{'childs'} )
	    {
		# Stay open while waiting for child
#		warn "  staying open...\n";
	    }
	    else
	    {
		# All jobs done for now
		debug(2,"All jobs done");
		$req->run_hook('done');
		close_callback($req->{'client'});
	    }

	    $timeout = TIMEOUT_SHORT; ### Get the jobs done quick
	}

	### Do background jobs if no req jobs waiting
	#
	unless( values %REQUEST )
	{
	    add_background_jobs() and
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

#	    warn "Waiting for a child\n";
#	    my $childs = $child->req->{'childs'};
#	    warn "  childs: $childs\n";
#	    sleep;
	}
	else
	{
	    if( $TERMINATE )
	    {
		# Exit asked to and nothing is in flux
		if( not keys %REQUEST and not keys %CHILD )
		{
		    if( $TERMINATE eq 'HUP' )
		    {
			# Make watchdog restart us
			exit 1;
		    }
		    elsif( $TERMINATE eq 'TERM' )
		    {
			# No restart
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
	}

    }
    debug(4,"Exiting  main_loop at level $LEVEL",-1);
    $LEVEL --;
}


sub switch_req
{
    # $_[0] => the new $req
    # $_[1] => force change (not used)

    if( $_[0] ne $REQ )
    {
	if( $REQ )
	{
	    warn "\nSwitching to req $_[0]->{reqnum}\n";

	    if( $REQ->{'s'} )
	    {
		# Store template error data (undocumented)
		$REQ->{'s'}{'template_error'} =
		    $Para::Frame::th->{'html'}{ _ERROR };
	    }

	    # Detatch %ENV
	    $REQ->{'env'} = {%ENV};
	}

	Para::Frame->run_hook(undef, 'before_switch_req');

	$U = undef;
	if( $REQ = $_[0] )
	{
	    if( my $s = $REQ->{'s'} )
	    {
		$U   = $s->u;
		$DEBUG  = $s->{'debug'};

		# Retrieve template error data (undocumented)
		$Para::Frame::th->{'html'}{ _ERROR } =
		    $s->{'template_error'};
	    }

	    # Attach %ENV
	    %ENV = %{$REQ->{'env'}};
	    $REQ->{'env'} = \%ENV;

	    $INDENT = $REQ->{'indent'};
	}
	else
	{
	    %ENV = undef;
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
	debug(0,"Getting value inside a fork");
	while( $_ = <$Para::Frame::Client::SOCK> )
	{
	    if( s/^([\w\-]{3,10})\0// )
	    {
		my $code = $1;
		debug(0,"Code $code");
		chomp;
		if( $code eq 'RESP' )
		{
		    my $val = $_;
		    debug(0,"RESP ($val)");
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


#    warn "Waiting for client\n";
    my $time = time;
    my $timeout = 3;
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
	    cluck "trace:";
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
		    handle_request( $client, \$INBUFFER{$client} );
		}
		elsif( $code eq 'CANCEL' )
		{
		    debug(0,"CANCEL client");
		    $DATALENGTH{$client} = 0;
		    close_callback($client);
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
	debug(4,"Done ($reason)");
    }
    else
    {
	warn "Done\n";
    }

    if( $client )
    {
	delete $REQUEST{$client};
	delete $INBUFFER{$client};
	undef $REQ;
	$SELECT->remove($client);
	close($client);
    }
    else # This is a bg job
    {
	delete $REQUEST{'background'};
	undef $REQ;
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

    while (($child_pid = waitpid(-1, POSIX::WNOHANG)) > 0)
    {
	warn "| Child $child_pid exited with status $?\n";

	if( my $child = delete $CHILD{$child_pid} )
	{
	    $child->deregister( $? );
	}
	else
	{
	    warn "|   No object registerd with PID $child_pid\n";
	    warn "|     This may be Date::Manip...\n";
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
	warn "\n\nStarted process $$ on ".scalar(localtime)."\n\n";
	Para::Frame->startup();
	open_logfile();
	POSIX::setsid             or die "Can't start a new session: $!";
	write_pidfile();
	kill 'USR1', $parent_pid; # Signal parent
	warn "\n\nStarted process $$ on ".scalar(localtime)."\n\n";
	Para::Frame::main_loop();
    }
}


sub add_background_jobs
{

    # Add background jobs to do unless the load is too high, uless we
    # waited too long anyway

    # Return if BG jobs already running
    return if $REQUEST{'background'};
    return if $TERMINATE;

    # Return it hasn't passed BGJOB_MAX secs since last time
    my $last_time = $BGJOBDATE ||= time;
    my $delta = time - $last_time;
    return if $delta < BGJOB_MAX;

    # Cache cleanup could safely be done here
    Para::Frame->run_hook(undef, 'busy_background_job', $delta);


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
    
    $REQNUM ++;
    warn "\n\nHandling request number $REQNUM (in background)\n";
    my $req = Para::Frame::Request->new_minimal($REQNUM);

    ### Reload updated modules
    Para::Frame::Reload->check_for_updates;

    ### Register the request
    $REQUEST{'background'} = $req;
    switch_req( $req );
    my $user_class = $Para::Frame::CFG->{'user_class'};
    my $bg_user = &{ $Para::Frame::CFG->{'bg_user_code'} };
    $user_class->change_current_user($bg_user);

    ### Debug info
    if( debug > 2 )
    {
	my $t = localtime;
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
    warn "\n\nHandling request number $REQNUM\n";

    ### Reload updated modules
    Para::Frame::Reload->check_for_updates;

    ### Create request ($REQ not yet set)
    my $req = new Para::Frame::Request( $REQNUM, $client, $recordref );

    ### Register the request
    $REQUEST{ $client } = $req;
    switch_req( $req ); 
 
    ### Further initialization that requires $REQ
    $req->ctype( $req->{'orig_ctype'} );
    $req->{'uri'} = $req->set_uri( $req->{'orig_uri'} );
    $req->{'s'}->route->init;

    # Authenticate user identity
    my $user_class = $Para::Frame::CFG->{'user_class'};
    $user_class->identify_user;     # Will set $s->{user}
    $user_class->authenticate_user;

    ### Debug info
    my $t = localtime;
    my $s = $req->s;
    warn sprintf("# %s %s - %s\n# Sid %s - Uid %d - debug %d\n",
		 $t->ymd,
		 $t->hms('.'),
		 $req->client_ip,
		 $s->id,
		 $s->u->id,
		 $s->{'debug'},
		 );
   
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
    }

    ### Clean up used globals
    # (undocumented)
    $s->{'template_error'} = $Para::Frame::th->{'html'}{ _ERROR } = '';
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

sub add_tt_filters
{
    my( $class, $type, $params, $dynamic ) = @_;

    my $context = $Para::Frame::th->{$type}->context;
    $dynamic ||= 0;

    foreach my $name ( keys %$params )
    {
	$context->define_filter( $name, $params->{$name}, $dynamic );
    }
}

sub incpath_generator
{
    unless( $REQ->{'incpath'} )
    {
	$REQ->{'incpath'} = [ map uri2file( $_."inc" )."/", @{$REQ->{'dirsteps'}} ];
	debug(4,"Incpath: @{$REQ->{'incpath'}}");
    }
    return $REQ->{'incpath'};
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

    $CFG = $cfg_in; # Assign to global var

    ### Set main debug level
    $DEBUG = $CFG->{'debug'} || 0;
    $Para::Frame::Client::DEBUG = $DEBUG;

    $CFG->{'dir_var'} ||= '/var';
    $CFG->{'dir_log'} ||= $CFG->{'dir_var'}."/log";
    $CFG->{'dir_run'} ||= $CFG->{'dir_var'}."/run";

    $CFG->{'paraframe'} ||= '/usr/local/paraframe';
    $CFG->{'paraframe_group'} ||= 'staff';


    # Site pages

    # Since one server can serve many websites, there should be a
    # on_site_change() hook for updating environment data (global
    # variables) for the specific site. The basic site dependant
    # configuration data are grouped in {'site'} subhash. You may want
    # to replace it depending on what site is requested

    my $site = $CFG->{'site'} ||= {};

    $site->{'webhome'}     ||= ''; # URL path to website home
    $site->{'last_step'};        # Default to undef
    $site->{'login_page'}  ||= $site->{'last_step'} || $site->{'webhome'}.'/';
    $site->{'logout_page'} ||= $site->{'webhome'}.'/';

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

    my %th_config =
	(
	 INCLUDE_PATH => [ \&incpath_generator, $CFG->{'paraframe'}."/inc" ],
	 PRE_PROCESS => 'header_prepare.tt',
	 POST_PROCESS => 'footer.tt',
	 TRIM => 1,
	 PRE_CHOMP => 1,
	 POST_CHOMP => 1,
	 RECURSION => 1,
	 PLUGIN_BASE => 'Para::Frame::Template::Plugin',
	 );


    $CFG->{'th'}{'html'} ||=
    {
	%th_config,
	ABSOLUTE => 1, ### TEST
	INTERPOLATE => 1,
	COMPILE_DIR =>  $CFG->{'paraframe'}.'/var/ttc/html',
    };

    $CFG->{'th'}{'html_pre'} ||=
    {
	%th_config,
	COMPILE_DIR =>  $CFG->{'paraframe'}.'/var/ttc/html_pre',
	TAG_STYLE => 'star',
    };

    $CFG->{'th'}{'plain'} ||=
    {
	INTERPOLATE => 1,
	COMPILE_DIR => $CFG->{'paraframe'}.'/var/ttc/plain',
	FILTERS =>
	{
	    'uri' => sub { CGI::escape($_[0]) },
	    'lf'  => sub { $_[0] =~ s/\r\n/\n/g; $_[0] },
	    'autoformat' => sub { autoformat($_[0]) },
	},
    };

    foreach my $ttype (keys %{$CFG->{'th'}})
    {
	$Para::Frame::th->{$ttype} =
	    Template->new(%{$CFG->{'th'}{$ttype}});
    }

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


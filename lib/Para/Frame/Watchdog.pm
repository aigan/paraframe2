package Para::Frame::Watchdog;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2009 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::Watchdog - Watches over the process

=cut

use 5.010;
use strict;
use warnings;

use IO::File;
use IO::Select;
use POSIX qw(WNOHANG);
use Proc::ProcessTable;
use Linux::SysInfo;
use Time::HiRes;
use Carp;
use Sys::CpuLoad;
use File::Basename; # dirname

use Para::Frame::Utils qw( chmod_file create_dir );
use Para::Frame::Time qw( now );
use Para::Frame::Sender;

our $PID;                  # The PID to watch
our $FH;                   # Server file-handle
our $CRASHCOUNTER;         # Number of crashes
our $CRASHTIME;

our $DO_CONNECTION_CHECK;
our $HARD_RESTART;
our $SHUTDOWN;             # Should we shut down the server?
our $DOWN;                 # Restart or shutdown in progress

our $MSGTYPE;              # Type of messages from server
our $CHECKTIME;            # Time of last proc check
our $CPU_TIME;             # user + system time
our $CPU_USAGE=0;          # Aproximate avarage usage
our $MEMORY_CLEAR_TIME;    # When to send memory message
our $USE_LOGFILE;          # Redirects STDERR to logfile
our $EMERGENCY_MODE;       # Experienced a crash. Maximum debug

our $SOCK;                 # Socket for sending
our @MESSAGE;              # Messages pipe


our $INTERVAL_CONNECTION_CHECK =  60;
our $INTERVAL_MAIN_LOOP        =  10;
our $LIMIT_MEMORY              ;
our $LIMIT_MEMORY_NOTICE       ;
our $LIMIT_MEMORY_BASE         =3600;
our $LIMIT_MEMORY_NOTICE_BASE  =2000;
our $LIMIT_MEMORY_MIN          = 150;
our $LIMIT_SYSTOTAL            =   1;
our $TIMEOUT_SERVER_STARTUP    =  45;
our $TIMEOUT_CONNECTION_CHECK  =  60;
our $LIMIT_CONNECTION_TRIES    =   5;
our $TIMEOUT_CREATE_FORK       =   5;
our $EMERGENCY_DEBUG_LEVEL     =   2;


sub debug; # Use special version of debug

# TODO: Proc::PidUtil

=head1 DESCRIPTION

Makes sure that the daemon runs.

Restarts it if it eats too much memory or if it craches.

Called by L<Para::Frame/daemonize> or L<Para::Frame/watchdog_startup>.

Uses C<lsof> to check if another process uses our port, and tries to
kill it if there is any. Works fine for restarting your daemon.

=cut


#######################################################################

=head2 startup

=cut

sub startup
{
    my( $class, $use_logfile )  = @_;

    configure($use_logfile);

    debug 1, "\n\nStarted process $$ on ".now()."\n\n";

    # Setup signal handling
    # This will be redefined in the fork
    #
    $SIG{CHLD} = \&REAPER;

    $SIG{TERM} = sub
    {
	terminate_server();
	exit 0;
    };

    $SIG{USR1} = sub
    {
	restart_server();
    };

    $SIG{HUP} = sub
    {
	restart_server();
    };

    return startup_in_fork();
}


#######################################################################

=head2 watch_loop

=cut

sub watch_loop
{
#    debug "startup succeeded";
    $Para::Frame::IN_STARTUP = 0; # Startup succeeded
    my $last_connection_check = time;
    while()
    {
#	debug "--in watch_loop";
	exit 0 if $SHUTDOWN;
	check_server_report();
	if( $DO_CONNECTION_CHECK )
	{
	    check_connection() or next;
	}
	check_process();

	# Do a connection check once a minute
	if( time > $last_connection_check + $INTERVAL_CONNECTION_CHECK )
	{
	    $DO_CONNECTION_CHECK ++;
	    $last_connection_check = time;
	}

	sleep $INTERVAL_MAIN_LOOP;
#	debug "--handle missed signals";
	&REAPER; # Handle missed calls (WHY ARE THEY MISSED?!)
    }
    debug "escaped watchdog main loop";
    exit 1;
}


#######################################################################

=head2 check_process

=cut

sub check_process
{
    # Since we handling $SIG{CHLD}, this is not needed
    unless( kill 0, $PID )
    {
	debug "Process realy gone?";
    }

    my $p = get_procinfo( $PID ) or return;

    my $size = $p->size / 1_000_000; # In MB
    my $time = $p->time;
    my $sys_time = Time::HiRes::time;
    if( $CHECKTIME )
    {
#	warn join '-', Sys::CpuLoad::load();
	my( $usage ) = (Sys::CpuLoad::load())[0]*100;
	my $systotal = memusage();
	$CPU_USAGE = ($CPU_USAGE * 2 + $usage ) / 3;

	if( debug > 2 or
	    $CPU_USAGE > 200 or
	    $size > $LIMIT_MEMORY_NOTICE or
	    $systotal > $LIMIT_SYSTOTAL
	  )
	{
	    debug sprintf( "Serverstat %.2d%% CPU, %5d MB. %d%% sysmem",
			   $usage, $size, $systotal*100  );
	}

	if( $systotal > $LIMIT_SYSTOTAL and
	    ( $LIMIT_MEMORY > $LIMIT_MEMORY_MIN * 2  ) )
	{
	    debug sprintf "Systotal: %.2f", $systotal;
	    my $total = ((($LIMIT_MEMORY - $LIMIT_MEMORY_MIN ) * 0.9)
			 + $LIMIT_MEMORY_MIN );
	    my $note  = ((($LIMIT_MEMORY_NOTICE - $LIMIT_MEMORY_MIN ) * 0.9)
			 + $LIMIT_MEMORY_MIN );
	    debug "Shrinking memory limits";
	    debug sprintf "  Notice : %d -> %d", $LIMIT_MEMORY_NOTICE, $note;
	    debug sprintf "  Max    : %d -> %d", $LIMIT_MEMORY, $total;
	    $LIMIT_MEMORY = $total;
	    $LIMIT_MEMORY_NOTICE = $note;
	}
    }

    $CHECKTIME = $sys_time;

    # Kill if server uses more than LIMIT_MEMORY MB of memory
    if( $size > $LIMIT_MEMORY )
    {
	debug "Server using to much memory";
	debug sprintf "  Using: %d MB", $size;
	debug sprintf "  Limit: %d MB", $LIMIT_MEMORY;
	debug sprintf "  Total system memory used: %d%%", (100*memusage());
	debug "  Restarting...";
	restart_server();
    }
    elsif( $size > ($LIMIT_MEMORY + $LIMIT_MEMORY_NOTICE )/2 and
	   time > $MEMORY_CLEAR_TIME + $TIMEOUT_CONNECTION_CHECK )
    {
	debug "Server using to much memory";
	send_to_server('HUP');
	debug "  Sent soft HUP to $PID";
 	$MEMORY_CLEAR_TIME = time;
    }
    elsif( $size > $LIMIT_MEMORY_NOTICE and
	   time > $MEMORY_CLEAR_TIME + $TIMEOUT_CONNECTION_CHECK  )
    {
	debug "Sending memory notice to server";
	send_to_server('MEMORY', \$size );
	$MEMORY_CLEAR_TIME = time;
    }
}


#######################################################################

=head2 wait_for_server_startup

=cut

sub wait_for_server_setup
{
    while( my( $type, @args ) =
	   get_next_server_message($TIMEOUT_SERVER_STARTUP) )
    {
	next unless $type;

	if( $type eq 'STARTED' )
	{
	    return 1;
	}
	elsif( $type eq 'Loading' )
	{
	    print "Loading @args\n";
	}
	elsif( $type eq 'MAINLOOP' )
	{
	    # ignoring...
	}
	else
	{
	    debug "Unexpected message during startup: $type @args";
	    return watchdog_crash();
	}
    }

    debug "Server failed to reach main loop (TIMEOUT)";
    return watchdog_crash();
}


#######################################################################

=head2 check_server_port

=cut

sub check_server_report
{
    while()
    {
	my( $type, @args ) = get_next_server_message();
	last unless $type;

	if( $type eq 'TERMINATE' )
	{
	    debug "Got request to terminate server";
	    terminate_server();
	    exit 0;
	}
	elsif( $type eq 'PING')
	{
	    debug "Got a ping request. Checking connection";
	    check_connection();
	}
	elsif( $type eq 'DOWN')
	{
	    debug "Server going down";
	    $DOWN = 1;
	}

#	debug "--get_next_server_message";
    }
}


#######################################################################

=head2 terminate_server

=cut

sub terminate_server
{
    send_to_server('TERM');
    debug 1,"  Sent soft TERM to $PID";

    # Waiting for server to TERM
    my $signal_time = time;
    while( kill 0, $PID )
    {
	if( time > $signal_time + $TIMEOUT_CONNECTION_CHECK + $TIMEOUT_CREATE_FORK )
	{
	    kill 'KILL', $PID; ## Terminate server
	    debug 1,"  Sent hard KILL to $PID";
	}
	elsif( time > $signal_time + $TIMEOUT_CONNECTION_CHECK )
	{
	    kill 'TERM', $PID; ## Terminate server
	    debug 1,"  Sent hard TERM to $PID";

	}
	sleep 1;
    }
}


#######################################################################

=head2 restart_server

=cut

sub restart_server
{
    my( $hard ) = @_;

    my $pid = $PID; # $PID will change on new fork
    send_to_server('HUP');
    debug 1,"  Sent soft HUP to $PID";

    # Waiting for server to HUP
    my $signal_time = time;
    my $grace_time = $hard ? 0 : $TIMEOUT_CONNECTION_CHECK;
    my $sent = '';

    while( $pid == $PID )
    {
	sleep 2;
	if( $sent eq 'kill' )
	{
	    debug "Waiting for restart of server";
	    sleep 10;
	}
	elsif( time > $signal_time + $grace_time + 30 )
	{
	    next if $sent eq 'KILL';
	    $sent = 'KILL';
	    $HARD_RESTART = 1;
	    kill 'KILL', $pid;  ## Terminate server
	    debug "  Sent hard KILL to $pid";
	    last;
	}
	elsif( time > $signal_time + $grace_time + 20 )
	{
	    next if $sent eq 'TERM';
	    $sent = 'TERM';
	    $HARD_RESTART = 1;
	    kill 'TERM', $pid;  ## Terminate server
	    debug "  Sent hard TERM to $pid";
	}
	elsif( time > $signal_time + $grace_time )
	{
	    next if $sent eq 'HUP';
	    $sent = 'HUP';
	    kill 'HUP', $PID; ## Terminate server
	    debug "  Sent hard HUP to $PID";
	}

	&REAPER; # Handle missed calls
    }
}


#######################################################################

=head2 get_next_server_message

=cut

sub get_next_server_message
{
    if( my $msg = shift @MESSAGE )
    {
	return( @$msg );
    }

    get_server_message( @_ );

    if( my $msg = shift @MESSAGE )
    {
	return( @$msg );
    }

    return undef;
}


#######################################################################

=head2 get_server_message

=cut

sub get_server_message
{
    my( $timeout ) = @_;
    if( $timeout )
    {
	# Wait for a report
	IO::Select->new($FH)->can_read($timeout);
    }

    while( my $report = $FH->getline )
    {
	chomp $report;
	my( $type, $argstring ) = split / /, $report;

	my $argformat = $MSGTYPE->{$type};
	unless( defined $argformat )
	{
	    debug "---> Got unrecognized server report: $report ($type)";
	    next;
	}

#	debug "Server reported $type\n";

	# Just return type if no argument was expected
	if( $argformat == 0 and not $argstring )
	{
	    push @MESSAGE, [$type];
	    next;
	}

	$argstring = '' unless defined $argstring; # accept 0
	my( @args ) = $argstring =~ m/$argformat/;
	if( defined $+ ) # Did we match?
	{
#	    debug "  returning args @args";
	    push @MESSAGE, [$type, @args];
	}
	else
	{
	    debug "Server repored $type\n";
	    debug "  Argstring '$argstring' did not match argformat '$argformat'\n";
	}
    }

    return 1;
}


#######################################################################

=head2 check_connection

=cut

sub check_connection
{
    debug 4, "  Checking connection\n";
    my $port = $Para::Frame::CFG->{'port'};
    my $try = 0;
    $DO_CONNECTION_CHECK = 0;

  CONNECTION_TRY:
    while()
    {
	check_server_report(); return 0 if $DOWN;

	$try ++;
	debug 4, "  Check $try";

	send_to_server('PING');
	unless( $SOCK )
	{
	    debug "Failed to send PING to server";
	    return watchdog_crash();
	}

	my $select = IO::Select->new($SOCK);

	# Waiting for the response in TIMEOUT_CONNECTION_CHECK seconds
	my $waited     = 0;
	while()
	{
	    if( $select->can_read( $INTERVAL_MAIN_LOOP ) )
	    {
		my $resp = $SOCK->getline or last; ### During restart?
		my $length;

		if( $resp =~ s/^(\d+)\x00// )
		{
		    debug(4,"Setting length to $1");
		    $length = $1;
		    debug(4, "Leaving '$resp'");
		}

		if( $resp eq "PONG\0" )
		{
		    debug 4, "    Working!\n";
		    last CONNECTION_TRY;
		}
		else
		{
		    chomp $resp;
		    debug "Got response '$resp' on PING";
		    last;
		}
	    }
	    else
	    {
		# Do some process cheking while we waite
		check_process();

		$waited += $INTERVAL_MAIN_LOOP;
	        next unless $waited >= $TIMEOUT_CONNECTION_CHECK;
	    }

	    debug "  Timeout while waiting for ping response";
	    restart_server(1); # Do hard restart. No extra waiting
	    last CONNECTION_TRY;
	}

	if( $try >= $LIMIT_CONNECTION_TRIES )
	{
	    debug "Tried $try times";
	    return watchdog_crash();
	}
    }
    return 1;
}


#######################################################################

=head2 on_crash

=cut

sub on_crash
{
    $CRASHCOUNTER ++;
    $CRASHTIME = now();
    if( $HARD_RESTART )
    {
	debug "There was a request for a hard restart";
	$HARD_RESTART = 0;
    }

    if( $CRASHCOUNTER > 10 )
    {
	debug "Restartcounter at $CRASHCOUNTER";
	debug "Doing a clean restart";
	open STDOUT, '>/dev/null' or die "Can't write to /dev/null: $!";
	exec("$0 @ARGV &"); warn "Exec failed: $!"; sleep 1;
	debug "executing $0";
	exec("$0 @ARGV &"); warn "Exec failed: $!";
    }

    debug "\n\n\nRestart $CRASHCOUNTER at $CRASHTIME\n\n\n";

    return startup_in_fork();
}


#######################################################################

=head2 watchdog_crash

=cut

sub watchdog_crash
{
    # Bail out if this was under startup
    exit 1 if $Para::Frame::IN_STARTUP;


    $EMERGENCY_MODE++;
    debug "\n\nWatchdog got an unexpected situation ($EMERGENCY_MODE)";


    if( $Para::Frame::DEBUG <= $EMERGENCY_DEBUG_LEVEL )
    {
	$Para::Frame::DEBUG =
	    $Para::Frame::CFG->{'debug'} =
	    $EMERGENCY_DEBUG_LEVEL;
	debug "Raising global debug to level $Para::Frame::DEBUG";
    }

    # Kill all children
    if( $PID and kill 0, $PID )
    {
	restart_server(1);
	# on_crash will be called from REAPER
    }
    else
    {
	on_crash();
    }

    return 0; # Make caller go back to main loop
}


#######################################################################

=head2 startup_in_fork

=cut

sub startup_in_fork
{
    # Code from Para::Frame::Request->create_fork()

    &REAPER; # Handle missed calls

    my $sleep_count = 0;
    my $fh = new IO::File;
#    my $write_fh = new IO::File;  # Alternative top open -|

    # Do not expect exceptions during forking...
    # Make these undef in the server fork:
    $PID = undef;
    $FH  = undef;

    $CPU_TIME  = undef;
    $CHECKTIME = undef;

    $LIMIT_MEMORY = $LIMIT_MEMORY_BASE;
    $LIMIT_MEMORY_NOTICE = $LIMIT_MEMORY_NOTICE_BASE;


    # Must autoflush STDOUT
    select STDOUT; $|=1;

    do
    {
	$PID = open($fh, "-|");
#	pipe( $fh, $write_fh );
#	$PID = fork;
	unless( defined $PID )
	{
	    debug(0,"cannot fork: $!");
	    exit 1 if $sleep_count++ >= $TIMEOUT_CREATE_FORK;
	    sleep 1;
	}
    } until defined $PID;

    if( !$PID )
    {
	### --> child

#	open STDOUT, ">&", $write_fh; ### DEBUG

	# Reset signal handlers
	$SIG{CHLD} = 'DEFAULT';
	$SIG{USR1} = 'DEFAULT';
	$SIG{TERM} = 'DEFAULT';
	$SIG{HUP}  = 'DEFAULT';

	kill_competition();
	Para::Frame->startup();
	open_logfile() if $USE_LOGFILE;
	Para::Frame::main_loop();
	debug "Got outside main_loop";
	exit 1;
    }

    # Better setting global $FH after the forking
    $fh->blocking(0); # No blocking
    $FH = $fh;

    # Wait for server response
    wait_for_server_setup() or return 0;

    # schedule connection check (must be done outside REAPER)
    $DO_CONNECTION_CHECK ++;

    debug 1, "Watching $PID";
    return 1;
}


#######################################################################

=head2 REAPER

=cut

sub REAPER
{
    # Taken from example in perl doc

#    debug "In reaper";

    my $child_pid;
    # If a second child dies while in the signal handler caused by the
    # first death, we won't get another signal. So must loop here else
    # we will leave the unreaped child as a zombie. And the next time
    # two children die we get another zombie. And so on.

    while (($child_pid = waitpid(-1, WNOHANG)) > 0)
    {
	debug "Child $child_pid exited with status $?";

	if( $child_pid == $PID )
	{
	    if( $? == 0 )
	    {
		debug "Server shut down whithout problems";
		$SHUTDOWN = 1;
	    }
	    elsif( $? == 15 and not $HARD_RESTART )
	    {
		debug "Server got a TERM signal. I will not restart it";
		$SHUTDOWN = 1;
	    }
	    elsif( $? == 9 and not $HARD_RESTART )
	    {
		debug "Server got a KILL signal. I will not restart it";
		$SHUTDOWN = 1;
	    }
	    elsif( $? == 25088 )
	    {
		debug "Another process is using this port";
		exit $?;
	    }
	    else
	    {
		if( $Para::Frame::IN_STARTUP )
		{
		    debug "  We are still in startup";
		    debug "  Ignoring this signal...";
		    return $?;
#		    exit $?;
		}

		$DOWN = 0;
		on_crash();
	    }
	}
	else
	{
	    debug "Expected $PID\n";
	    debug "I don't know about that child ($child_pid)!";
	    exit 1;
	}
    }
    $SIG{CHLD} = \&REAPER;  # still loathe sysV
}


#######################################################################

=head2 debug

=cut

sub debug
{
    my( $level, $message ) = @_;

#    Carp::cluck;
    return $Para::Frame::DEBUG unless defined $level;

    unless( $message )
    {
	$message = $level;
	$level = 0;
    }

    if( $Para::Frame::DEBUG >= $level )
    {
	my $prefix =  "#### Watchdog ";

	$message =~ s/^(\n*)//;
	my $prespace = $1 || '';

	chomp $message;
	my $datestr = scalar(localtime);
	warn $prespace . $prefix . $datestr . ": " . $message . "\n";
    }

    return "";
}


#######################################################################

=head2 get_procinfo

=cut

sub get_procinfo
{
    my( $pid ) = @_;

    my $pt = Proc::ProcessTable->new( 'cache_ttys' => 1 )->table;

    my $i=0;
    my $p;
    while()
    {
	$p = $pt->[$i] or last;
	$p->pid == $pid and last;
	$i++;
    }
    unless( $p )
    {
	debug "Failed to find the process $pid";
	return undef;
    }

    return $p;
}


#######################################################################

=head2 send_to_server

=cut

sub send_to_server
{
    my( $code, $valref ) = @_;

    my $DEBUG = 1;

    exit 0 if $SHUTDOWN; # Bail out if requested to...

    my @cfg =
	(
	 PeerAddr => 'localhost',
	 PeerPort => $Para::Frame::CFG->{'port'},
	 Proto    => 'tcp',
	 Timeout  => 5,
	 );

    $SOCK = IO::Socket::INET->new(@cfg);

    my $try = 1;
    while( not $SOCK )
    {
	check_server_report(); return 0 if $DOWN;

	$try ++;
	warn "$$:   Trying again to connect to server ($try)\n" if $DEBUG;

	$SOCK = IO::Socket::INET->new(@cfg);

	last if $SOCK;

	if( $try >= 5 )
	{
	    warn "$$: Tried connecting to server $try times - Giving up!\n";
	    last;
	}

	sleep 1;
    }

    if( $SOCK )
    {
	binmode( $SOCK, ':raw' );
	warn "$$: Established connection to server\n" if $DEBUG > 3;
    }
    else
    {
	debug "Failed to connect to server";
	return undef;
    }

    ############# CONNECTION ESTABLISHED

    $valref ||= \ "1";
    my $length_code = length($$valref) + length($code) + 1;

    my $data = "$length_code\x00$code\x00" . $$valref;

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
	    check_server_report(); return 0 if $DOWN;

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

=head2 open_logfile

=cut

sub open_logfile
{
    my $log = $Para::Frame::CFG->{'logfile'};
    create_dir( dirname $log);

    open STDERR, '>>', $log   or die "Can't append to $log: $!";
    warn "\nStarted process $$ on ".now()."\n\n";

    chmod_file($log);
}


#######################################################################

=head2 kill_competition

=cut

sub kill_competition
{

    # Kills all processes using the same port.  If not root (and we
    # should not be), it lists processes by the same user.

    my $port = $Para::Frame::CFG->{'port'};
    my $proclist = get_lsof({port => $port });
    my $ppid = getppid();

    if( @$proclist )
    {
	my @pids;
	foreach my $p ( @$proclist )
	{
	    my $pid = $p->{pid};
	    next if $pid == $ppid;
	    next if $pid == $$;

	    unless( @pids ) # say once...
	    {
		debug "Found a process using our port: $port";
	    }

	    debug "Killing pid $pid: $p->{command}";
	    kill 9, $pid;
	    push @pids, $pid;
	}

	foreach my $pid ( @pids )
	{
	    while( kill 0, $pid )
	    {
		debug "  waiting for $pid to exit";
		sleep 1;
	    }
	}

	return scalar @$proclist;
    }
    return 0;
}


#######################################################################

=head2 get_lsof

=cut

sub get_lsof
{
    my( $args ) = @_;

    $args ||= {};

    my @params = "-FRucT";

    if( $args->{'port'} )
    {
	push @params, "-i", ":".$args->{'port'};
    }
    else
    {
	die "not implemented (no port given)";
    }

    my $cmdline = join " ", 'lsof', '-V', @params;

    my $rec = {};
    my @list;


    my %parser =
	(
	 p => qr/^\d+$/,
	 R => qr/^\d+$/,
	 c => qr/.*/,
	 u => qr/^\d+$/,
	 T => qr/^(ST|QR|QS)=/,
	 );

    my %fields =
	(
	 p => 'pid',
	 R => 'ppid',
	 c => 'command',
	 u => 'uid',
	 T =>
	 {
	     QR => 'read_queue_size',
	     QS => 'send_queue_size',
	     ST => 'connection_state',
	 },
	 );

    debug 2, "Reading from $cmdline\n";
    open(STATUS, "$cmdline 2>&1 |")
	or die "can't fork $cmdline: $!\n";
    while(<STATUS>)
    {
	chomp;

	my $field  = substr $_, 0,1,'';

	unless( $parser{$field} )
	{
	    get_lsof_parse_message("$field$_");
	    last;
	}

	unless( $_ =~ m/$parser{$field}/ )
	{
	    get_lsof_parse_message("$field$_");
	    last;
	}

	if( $field eq 'p' )
	{
	    if( $rec->{'pid'} )
	    {
		push @list, $rec;
	    }
	    $rec = {};
	}

	if( $field eq 'T' )
	{
	    my( $type, $info ) = split /=/, $_;
	    $rec->{$fields{'T'}{$type}} = $info;
	}
	else
	{
	    $rec->{$fields{$field}} = $_;
	}
    }
    close STATUS;

    if( $rec->{'pid'} )
    {
	push @list, $rec;
    }


    if( $! )
    {
	debug "bad result: $!\n";
    }

    if( $? == -1 )
    {
	debug "failed to execute: $!\n";
    }
    elsif( $? & 127 )
    {
	debug "child died with signal %d, %s coredump\n",
	($? & 127),  ($? & 128) ? 'with' : 'without';
    }
    elsif( $? )
    {
	my $exit =  $? >> 8;
	if( $exit > 1 )
	{
	    debug "child exited with value $exit\n";
	}
    }

    return \@list;
}


#######################################################################

=head2 memusage

=cut

sub memusage
{
    my $sysinfo = Linux::SysInfo::sysinfo;

    my $total = $sysinfo->{'totalram'};
    my $free = $sysinfo->{'freeram'};
    my $buffer = $sysinfo->{'bufferram'};
    my $swap = $sysinfo->{'totalswap'} - $sysinfo->{'freeswap'};

    my $usage = $total - $free - $buffer + $swap;
    debug 2, "Usage: $usage";

    return( $usage / $total );
}


#######################################################################

=head2 get_lsof_parse_message

=cut

sub get_lsof_parse_message
{
    my( $msg ) = @_;

    if( $msg =~ /Internet address not located/ )
    {
	# All good!
	debug 2, $msg;
    }
    else
    {
	# Could be bad!
	debug $msg;
    }
}


#######################################################################

=head2 configure

=cut

sub configure
{
    $USE_LOGFILE = shift;

    $CRASHCOUNTER = 0;
    $DO_CONNECTION_CHECK = 0;
    $Para::Frame::IN_STARTUP = 1;
    $MEMORY_CLEAR_TIME = 0;
    $HARD_RESTART = 0;
    $EMERGENCY_MODE = 0;
    $SHUTDOWN = 0;
    $DOWN = 0;
    $SOCK = undef;
    @MESSAGE = ();

    # Message label and format of the arguments
    $MSGTYPE =
    {
        MAINLOOP => qr/^(\d+)$/,
	TERMINATE => 0,
        STARTED => 0,
        DOWN => 0,
        PING => 0,
	'Loading' => qr/(.*)/,
    };
}


#######################################################################

=head2 END

=cut

END
{
    # Resetting signal handlers
    $SIG{CHLD} = 'DEFAULT';
    $SIG{TERM} = 'DEFAULT';
    $SIG{USR1} = 'DEFAULT';
    $SIG{HUP} = 'DEFAULT';

    if( $PID )
    {
	# In watchdog
	debug("Closing down paraframe\n\n");
    }
}

#######################################################################

=head1 SEE ALSO

L<Para::Frame>

=cut


1;

#  $Id$  -*-cperl-*-
package Para::Frame::Watchdog;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Watchdog class
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

Para::Frame::Watchdog - Watches over the process

=cut

use strict;
use IO::File;
use IO::Select;
use POSIX;
use Proc::ProcessTable;
use Time::HiRes;
use Carp;
use Data::Dumper;
use Sys::CpuLoad;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Utils qw( chmod_file );
use Para::Frame::Time qw( now );
use Para::Frame::Client;

our $PID;                  # The PID to watch
our $FH;                   # Server file-handle
our $CRASHCOUNTER;         # Number of crashes
our $CRASHTIME;
our $DO_CONNECTION_CHECK;
our $HARD_RESTART;
our $SHUTDOWN;             # Should we shut down the server?
our $MSGTYPE;              # Type of messages from server 
our $CHECKTIME;            # Time of last proc check
our $CPU_TIME;             # user + system time
our $CPU_USAGE=0;          # Aproximate avarage usage
our $MEMORY_CLEAR_TIME;    # When to send memory message
our $USE_LOGFILE;          # Redirects STDERR to logfile
our $EMERGENCY_MODE;       # Experienced a crash. Maximum debug

use constant INTERVAL_CONNECTION_CHECK =>  60;
use constant INTERVAL_MAIN_LOOP        =>  10;
use constant LIMIT_MEMORY              =>3600;
use constant LIMIT_MEMORY_NOTICE       => 700;
use constant TIMEOUT_SERVER_STARTUP    =>  45;
use constant TIMEOUT_CONNECTION_CHECK  =>  60;
use constant LIMIT_CONNECTION_TRIES    =>   5;
use constant TIMEOUT_CREATE_FORK       =>   5;
use constant EMERGENCY_DEBUG_LEVEL     =>   2;

sub debug; # Use special version of debug

# TODO: Proc::PidUtil

=head1 DESCRIPTION

Makes sure that the daemon runs.

Restarts it if it eats too much memory or if it craches.

Called by L<Para::Frame/daemonize> or L<Para::Frame/watchdog_startup>.

Uses C<lsof> to check if another process uses our port, and tries to
kill it if there is any. Works fine for restarting your daemon.

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

sub watch_loop
{
    $Para::Frame::IN_STARTUP = 0; # Startup succeeded
    my $last_connection_check = time;
    while()
    {
	exit 0 if $SHUTDOWN;
	check_server_report();
	if( $DO_CONNECTION_CHECK )
	{
	    check_connection() or next;
	}
	check_process();

	# Do a connection check once a minute
	if( time > $last_connection_check + INTERVAL_CONNECTION_CHECK )
	{
	    $DO_CONNECTION_CHECK ++;
	    $last_connection_check = time;
	}

	sleep INTERVAL_MAIN_LOOP;
    }
    debug "escaped watchdog main loop";
    exit 1;
}

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
	$CPU_USAGE = ($CPU_USAGE * 2 + $usage ) / 3;

	if( debug > 3 or $CPU_USAGE > 200 or $size > LIMIT_MEMORY_NOTICE )
	{
	    debug sprintf( "Serverstat %.2d%% (%.2d%%) %5d MB",
			   $usage, $CPU_USAGE, $size );
	}
    }

    $CHECKTIME = $sys_time;

    # Kill if server uses more than LIMIT_MEMORY MB of memory
    if( $size > LIMIT_MEMORY )
    {
	debug "Server using to much memory";
	debug "  Restarting...";
	restart_server();
    }
    elsif( $size > (LIMIT_MEMORY + LIMIT_MEMORY_NOTICE )/2 and
	   time > $MEMORY_CLEAR_TIME + TIMEOUT_CONNECTION_CHECK )
    {
	debug "Server using to much memory";
	send_to_server('HUP');
	debug "  Sent soft HUP to $PID";
 	$MEMORY_CLEAR_TIME = time;
   }
    elsif( $size > LIMIT_MEMORY_NOTICE and
	   time > $MEMORY_CLEAR_TIME + TIMEOUT_CONNECTION_CHECK  )
    {
	debug "Sending memory notice to server";
	send_to_server('MEMORY', \$size );
	$MEMORY_CLEAR_TIME = time;
    }
}

sub wait_for_server_setup
{
    my( $type, $level ) = get_server_message(TIMEOUT_SERVER_STARTUP);
    unless( $type )
    {
	debug "Server failed to reach main loop (TIMEOUT)";
	return watchdog_crash();
    }
    if( $type ne 'MAINLOOP' )
    {
	debug "Expected MAINLOOP message (got '$type')";
	return watchdog_crash();
    }
    return 1;
}

sub check_server_report
{
    while()
    {
	my( $type, @args ) = get_server_message();
	last unless $type;

	if( $type eq 'TERMINATE' )
	{
	    debug "Got request to terminate server";
	    terminate_server();
	    exit 0;
	}
    }
}

sub terminate_server
{
    send_to_server('TERM');
    debug 1,"  Sent soft TERM to $PID";

    # Waiting for server to TERM
    my $signal_time = time;
    while( kill 0, $PID )
    {
	if( time > $signal_time + TIMEOUT_CONNECTION_CHECK + TIMEOUT_CREATE_FORK )
	{
	    kill 'KILL', $PID; ## Terminate server
	    debug 1,"  Sent hard KILL to $PID";
	}
	elsif( time > $signal_time + TIMEOUT_CONNECTION_CHECK )
	{
	    kill 'TERM', $PID; ## Terminate server
	    debug 1,"  Sent hard TERM to $PID";

	}
	sleep 1;
    }
}

sub restart_server
{
    my( $hard ) = @_;

    my $pid = $PID; # $PID will change on new fork
    send_to_server('HUP');
    debug 1,"  Sent soft HUP to $PID";

    # Waiting for server to HUP
    my $signal_time = time;
    my $grace_time = $hard ? 0 : TIMEOUT_CONNECTION_CHECK;
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
    }
}

sub get_server_message
{
    my( $timeout ) = @_;
    if( $timeout )
    {
	# Wait for a report
	IO::Select->new($FH)->can_read($timeout);
    }

    if( my $report = $FH->getline )
    {
	chomp $report;
	my( $type, $argstring ) = split / /, $report;

	my $argformat = $MSGTYPE->{$type};
	unless( defined $argformat )
	{
	    debug "---> Got unrecognized server report: $report ($type)";
	    return undef;
	}

	# Just return type if no argument was expected
	if( $argformat == 0 and not $argstring )
	{
	    return $type;
	}

	$argstring = '' unless defined $argstring; # accept 0
	my( @args ) = $argstring =~ m/$argformat/;
	if( defined $+ ) # Did we match?
	{
	    debug 4, "Server reported $type\n";
	    debug 5, "  returning args @args";
	    return $type, @args;
	}
	else
	{
	    debug "Server repored $type\n";
	    debug "  Argstring '$argstring' did not match argformat '$argformat'\n";
	}
    }
    return undef;
}

sub check_connection
{
    debug 4, "  Checking connection\n";
    my $port = $Para::Frame::CFG->{'port'};
    my $try = 0;
    $DO_CONNECTION_CHECK = 0;

  CONNECTION_TRY:
    while()
    {
	$try ++;
	debug 4, "  Check $try";

	my $sock = send_to_server('PING') or next;
	my $select = IO::Select->new($sock);

	# Waiting for the response in TIMEOUT_CONNECTION_CHECK seconds
	my $waited     = 0;
	while()
	{
	    if( $select->can_read( INTERVAL_MAIN_LOOP ) )
	    {
		my $resp = $sock->getline;
		if( $resp eq "PONG\n" )
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

		$waited += INTERVAL_MAIN_LOOP;
	        next unless $waited >= TIMEOUT_CONNECTION_CHECK;
	    }

	    debug "  Timeout while waiting for ping response";
	    restart_server(1); # Do hard restart. No extra waiting
	    last CONNECTION_TRY;
	}

	if( $try >= LIMIT_CONNECTION_TRIES )
	{
	    debug "Tried $try times";
	    return watchdog_crash();
	}
    }
    return 1;
}

sub on_crash
{
    $CRASHCOUNTER ++;
    $CRASHTIME = now();
    if( $HARD_RESTART )
    {
	debug "There was a request for a hard restart";
	$HARD_RESTART = 0;
    }
    debug "\n\n\nRestart $CRASHCOUNTER at $CRASHTIME\n\n\n";

    return startup_in_fork();
}

sub watchdog_crash
{
    # Bail out if this was under startup
    exit 1 if $Para::Frame::IN_STARTUP;


    $EMERGENCY_MODE++;
    debug "\n\nWatchdog got an unexpected situation ($EMERGENCY_MODE)";


    if( $Para::Frame::DEBUG <= EMERGENCY_DEBUG_LEVEL )
    {
	$Para::Frame::DEBUG =
	    $Para::Frame::Client::DEBUG =
	    $Para::Frame::CFG->{'debug'} =
	    EMERGENCY_DEBUG_LEVEL;
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

sub startup_in_fork
{
    # Code from Para::Frame::Request->create_fork()

    my $sleep_count = 0;
    my $fh = new IO::File;
#    my $write_fh = new IO::File;  # Alternative top open -|

    # Do not expect exceptions during forking...
    # Make these undef in the server fork:
    $PID = undef;
    $FH  = undef;

    $CPU_TIME  = undef;
    $CHECKTIME = undef;

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
	    exit 1 if $sleep_count++ >= TIMEOUT_CREATE_FORK;
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

sub send_to_server
{
    my( $code, $valref ) = @_;

    # Returns the socket. Undef on failure!

    exit 0 if $SHUTDOWN; # Bail out if requested to...

    my $port = $Para::Frame::CFG->{'port'};
    Para::Frame::Client::connect_to_server( $port );
    my $sock = $Para::Frame::Client::SOCK;
    unless( $sock )
    {
	debug "Failed to connect to server";
	return undef;
    }
    Para::Frame::Client::send_to_server($code, $valref);
    return $sock;
}

sub open_logfile
{
    my $log = $Para::Frame::CFG->{'logfile'};

    open STDERR, '>>', $log   or die "Can't append to $log: $!";
    warn "\nStarted process $$ on ".now()."\n\n";

    chmod_file($log);
}

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
	warn Dumper $args;
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

    # Message label and format of the arguments
    $MSGTYPE =
    {
        MAINLOOP => qr/^(\d+)$/,
	TERMINATE => 0,
	'Loading' => qr/(.*)/,
    };
}

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


=head1 SEE ALSO

L<Para::Frame>

=cut


1;

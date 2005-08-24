#  $Id$  -*-perl-*-
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
#   Copyright (C) 2004, 2005 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;
use IO::File;
use IO::Select;
use POSIX;
use Proc::ProcessTable;
use Time::HiRes;
BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Utils;
use Para::Frame::Time qw( now );
use Para::Frame::Client;

our $PID;                  # The PID to watch
our $FH;                   # Server file-handle
our $CRASHCOUNTER;         # Number of crashes
our $CRASHTIME;
our $DO_CONNECTION_CHECK;
our $MSGTYPE;              # Type of messages from server 
our $CHECKTIME;            # Time of last proc check
our $CPU_TIME;             # user + system time
our $CPU_USAGE;            # Aproximate avarage usage

use constant INTERVAL_CONNECTION_CHECK => 60;
use constant INTERVAL_MAIN_LOOP        => 10;
use constant LIMIT_MEMORY              => 500;
use constant TIMEOUT_SERVER_STARTUP    => 15;
use constant TIMEOUT_CONNECTION_CHECK  => 60;
use constant LIMIT_CONNECTION_TRIES    => 3;
use constant TIMEOUT_CREATE_FORK       => 5;

sub debug; # Use special version of debug

# TODO: Proc::PidUtil


sub startup
{
    debug "\n\nStarting\n";

    configure();

    # Setup signal handling
    # This will be redefined in the fork
    #
    $SIG{CHLD} = \&REAPER;

    startup_in_fork();

    debug 1, "  Going in to main loop, watching $PID";
    my $last_connection_check = time;
    while()
    {
	check_server_report();
	check_connection() if $DO_CONNECTION_CHECK;
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
    die "bailing out";
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
	my $cpu_delta = ($time - $CPU_TIME) || 0.00001;
	my $sys_delta = ($sys_time - $CHECKTIME) || 0.00001;
	my $usage = $cpu_delta/$sys_delta/10; # Get percent
	$CPU_USAGE = ($CPU_USAGE * 2 + $usage ) / 3;

	if( debug > 1 or $CPU_USAGE > 30 or $size > 200 )
	{
	    debug sprintf( "Serverstat %.2d%% (%.2d%%) %5d MB",
			   $usage, $CPU_USAGE, $size );
	}
    }

    $CPU_TIME = $time;
    $CHECKTIME = $sys_time;
    
    # Kill if server uses more than LIMIT_MEMORY MB of memory
    if( $size > LIMIT_MEMORY )
    {
	debug "Server using to much memory";
	debug "  Restarting...";
	terminate_server();
    }

}

sub wait_for_server_setup
{
    my( $type, $level ) = get_server_message(TIMEOUT_SERVER_STARTUP);
    unless( $type )
    {
	debug "Server failed to reach main loop";
	die "bailing out";
    }
    if( $type ne 'MAINLOOP' )
    {
	debug "Expected MAINLOOP message";
	die "bailing out";
    }
}

sub check_server_report
{
    my( $type, @args ) = get_server_message();

    if( $type eq 'TERMINATE' )
    {
	debug "Got request to terminate server";
	terminate_server();
	exit 0;
    }
}

sub terminate_server
{
    kill 'TERM', $PID; ## Terminate server
    debug 1,"  Sent TERM to $PID";
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
	    debug "---> Got unrecognized server report: $report";
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
	    debug 1, "Server repored $type\n";
	    debug 2, "  returning args @args";
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
    debug 1, "  Checking connection\n";
    my $port = $Para::Frame::CFG->{'port'};
    my $try = 0;
    $DO_CONNECTION_CHECK = 0;

  CONNECTION_TRY:
    while()
    {
	$try ++;
	debug 2, "  Check $try";
	Para::Frame::Client::connect_to_server( $port );
	my $sock = $Para::Frame::Client::SOCK or
	    die "Failed to connect to server\n";
	my $select = IO::Select->new($sock);

	Para::Frame::Client::send_to_server('PING');

	# Waiting for the response in TIMEOUT_CONNECTION_CHECK seconds
	my $waited     = 0;
	while()
	{
	    if( $select->can_read( INTERVAL_MAIN_LOOP ) )
	    {
		my $resp = $sock->getline;
		if( $resp eq "PONG\n" )
		{
		    debug 3, "    Working!\n";
		    last CONNECTION_TRY;
		}
		else
		{
		    chomp $resp;
		    debug "    Got response '$resp'";
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
	    terminate_server();
	    last CONNECTION_TRY;
	}

	if( $try >= LIMIT_CONNECTION_TRIES )
	{
	    die "Tried $try times; Bailing out";
	}
    }
}

sub on_crash
{
    $CRASHCOUNTER ++;
    $CRASHTIME = now();
    debug "Got crash $CRASHCOUNTER at $CRASHTIME";
    debug 1, "  Restarting paraframe";
    
    startup_in_fork();
}

sub startup_in_fork
{
    # Code from Para::Frame::Request->create_fork()

    my $sleep_count = 0;
    my $fh = new IO::File;

    # Do not expect exceptions during forking...
    # Make these undef in the server fork:
    $PID = undef;
    $FH  = undef;

    $CPU_TIME  = undef;
    $CHECKTIME = undef;

    do
    {
	$PID = open($fh, "-|");
	unless( defined $PID )
	{
	    debug(0,"cannot fork: $!");
	    die "bailing out" if $sleep_count++ >= TIMEOUT_CREATE_FORK;
	    sleep 1;
	}
    } until defined $PID;

    if( !$PID )
    {
	### --> child

	warn "Started paraframe in child\n";
	Para::Frame->startup();
	die "Got outside main_loop";
    }

    # Better setting global $FH after the forking
    $fh->blocking(0); # No blocking
    $FH = $fh;
    
    # Wait for server response
    wait_for_server_setup();

    # schedule connection check (must be done outside REAPER)
    $DO_CONNECTION_CHECK ++;
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
	debug 1, "Child $child_pid exited with status $?";

	if( $child_pid == $PID )
	{
	    on_crash();
	}
	else
	{
	    debug "Expected $PID\n";
	    die "I don't know about that child ($child_pid)!\n";
	}
    }
    $SIG{CHLD} = \&REAPER;  # still loathe sysV
}

sub debug
{
    my( $level, $message ) = @_;

    return $Para::Frame::DEBUG unless defined $level;

    unless( $message )
    {
	$message = $level;
    }

    if( $Para::Frame::DEBUG >= $level )
    {
	my $prefix =  "#### Watchdog: ";

	$message =~ s/^(\n*)//;
	my $prespace = $1 || '';

	chomp $message;
	warn $prespace . $prefix . $message . "\n";
    }
    
    return 1;
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

sub configure
{
    $CRASHCOUNTER = 0;
    $DO_CONNECTION_CHECK = 0;
    
    # Message label and format of the arguments
    $MSGTYPE =
    {
        MAINLOOP => qr/^(\d+)$/,
	TERMINATE => 0,
    };
}

1;

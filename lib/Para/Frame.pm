package Para::Frame 2.12;
#=============================================================================
#
# AUTHOR
#		Jonas Liljegren		<jonas@paranormal.se>
#
# COPYRIGHT
#		Copyright (C) 2004-2022 Jonas Liljegren.	All Rights Reserved.
#
#		This module is free software; you can redistribute it and/or
#		modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Para::Frame - Web application framework

=cut

use 5.012;
use warnings;

use IO::Socket 1.18;
use IO::Select;
use Socket;
use POSIX qw( locale_h WNOHANG BUFSIZ );
use Text::Autoformat;						#exports autoformat()
use Time::HiRes qw( time usleep );
use Carp qw( cluck confess carp croak longmess );
use Sys::CpuLoad;
use DateTime::TimeZone;
use DateTime::Format::Strptime;
use Cwd qw( abs_path );
use File::Basename;							# dirname
#use Template::Stash::ForceUTF8;
#use FreezeThaw qw( thaw );
use Storable qw( thaw );
use Number::Format;

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw catch run_error_hooks debug create_file chmod_file fqdn datadump client_send create_dir client_str );
#use Para::Frame::Template::Stash::CheckUTF8;
use Para::Frame::Unicode;
use Para::Frame::Watchdog;
use Para::Frame::Widget;
use Para::Frame::Burner;
use Para::Frame::Time qw( now );
use Para::Frame::L10N qw( loc );
use Para::Frame::Email::Address;
use Para::Frame::L10N;
use Para::Frame::Worker;
use Para::Frame::URI;
use Para::Frame::Sender;
use Para::Frame::Request;


use constant TIMEOUT_LONG		=>	 5;
use constant TIMEOUT_SHORT	=>	 0.000;
use constant BGJOB_MAX			=>	 8;			 # At most
use constant BGJOB_MED			=>	12;			 # Even if no visitors
use constant BGJOB_MIN			=>	60 * 15; # At least this often
use constant BGJOB_CPU			=>	 2.0;

# Do not init variables here, since this will be redone each time code is updated
our $SERVER			;
our $DEBUG			;
our $INDENT			;
our @JOBS				;								##not used...
our %CONN				;								# Connection data
our %REQUEST		;								# key is $client or 'background-...'
#our %RESPONSE	 ;					 # Holds client response for req and subreq
#our %INBUFFER	 ;
#our %DATALENGTH ;
our $REQ				;
our $REQ_LAST		;							 # Remeber last $REQ beyond a undef $REQ
our $U					;
our $REQNUM			;
our %SESSION		;
our $SELECT			;
our $CFG				;
our %HOOK				;
our $PARAMS			;
our %CHILD			;
our $LEVEL			;
our $BGJOBDATE	;
our $BGJOBNR		;
our @BGJOBS_PENDING;						# New jobs to be added in background
our $TERMINATE	;
our $MEMORY			;
our $IN_STARTUP ;							 # True until we reach the watchdog loop
our $ACTIVE_PIDFILE;					 # The PID indicated by existing pidfile
our $LAST				;							 # The last entering of the main loop
our %WORKER			;
our @WORKER_IDLE;
our %IOAGAIN		;

# More globals:
# $WATCHDOG_ACTIVE
# $FORK

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

	 <FilesMatch ".tt$|^$">
		 SetHandler perl-script
	 </FilesMatch>
	 PerlHandler Para::Frame::Client
	 ErrorDocument 404 /page_not_found.tt
	 PerlSetVar port 7788

In some/public/file.tt :

	 [% META title="Hello world" %]
	 <p>This is a simple template</p>

=cut


##############################################################################

BEGIN
{
	# Initializing hooks. For determining that they exists
	foreach my $hook (qw( on_startup
												on_memory
												on_error_detect
												on_fork
												done
												before_user_login
												user_login
												before_user_logout
												after_user_logout
												after_db_connect
												before_db_commit
												after_db_rollback
												before_switch_req
												before_render_output
												busy_background_job
												add_background_jobs
												after_bookmark
												after_action_success
												on_first_response
												on_reload
										 ))
	{
		$HOOK{$hook} ||= [];
	}

	# Errors to regard as temporary failures during socket IO
	%IOAGAIN =
		(
		 4 => 1,										# Interrupted system call
		 11 => 1,										# Try again
		);

}

##############################################################################

=head2 startup

=cut

sub startup
{
	my( $class ) = @_;

	# Site pages
	#
	unless ( $Para::Frame::CFG->{'site_class'}->get('default') )
	{
		croak "No default site registred";
	}


	my $port = $CFG->{'port'};

	# Set up the tcp server. Must do this before chroot.
	$SERVER= IO::Socket::INET->new(
																 LocalPort	=> $port,
																 Proto			=> 'tcp',
																 Listen			=> 10, # max 5? max 128?
																 ReuseAddr	=> 1,
																)
		or (die "Cannot connect to socket $port: $@\n");

	warn "Connected to port $port\n";

	nonblock($SERVER);
	$SELECT = IO::Select->new($SERVER);

	# Setup signal handling
	$SIG{CHLD} = \&REAPER;

	$LEVEL			= 0;
	$TERMINATE	= 0;
	$MEMORY			= 0;
#		 $IN_STARTUP = 0; # This is set from Watchdog

	# No REQ exists yet!
	Para::Frame->run_hook(undef, 'on_startup'); # before worker_startup

	$Template::BINMODE = ':utf8';

	# Start up workers early in order to get a small memory footprint
	if ( $CFG->{'worker_startup'} )
	{
		Para::Frame::Worker->create_idle_worker( $CFG->{'worker_startup'} );
	}

	warn "Setup complete, accepting connections\n";
	print "STARTED\n";
	$IN_STARTUP = 0;
	return;
}

##############################################################################

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


##############################################################################

=head2 main_loop

=cut

sub main_loop
{
	my( $child, $timeout ) = @_;

	# Optional $timeout params used for convaying how much in a hurry
	# the yielding party is. Espacially, if it's waiting for something
	# and realy want to give that something some time

	if ( $child )
	{
		$LEVEL ++;
	}

	$LAST = time;							# To give info about if it's time to yield

#		 Para::Frame::Logging->this_level(5);
	debug(5,"Entering main_loop at level $LEVEL",1) if $LEVEL;
	print "MAINLOOP $LEVEL\n" unless $Para::Frame::FORK or not $Para::Frame::WATCHDOG_ACTIVE;
#		 print "FH ".$Para::Frame::Watchdog::FH;

	$timeout ||= TIMEOUT_SHORT;

	while (1)
	{
		# The algorithm was adopted from perlmoo by Joey Hess
		# <joey@kitenet.net>.

		my $exit_action = eval
		{
#						 if( $timeout == TIMEOUT_LONG )
#						 {
#								 debug "waiting for read on socket..."; ### DEBUG
#						 }
#						 debug "can_read $SELECT with timeout $timeout for ".
#							 $SELECT->count()." handles";
#						 foreach my $cl ( $SELECT->handles )
#						 {
#								 debug " * $cl is ".($cl->connected?"connected":"DISCONNECTED");
#						 }


			### Recieve from clients
			#
			recieve_from_clients( $timeout );
			handle_recieved_data();


#						 while ( my( $client ) = $SELECT->can_read( $timeout ) )
#						 {
#								 if ( $client == $SERVER )
#								 {
#										 # Accept connection even if we should $TERMINATE since
#										 # it could be communication for finishing existing
#										 # requests
#
#										 add_client( $client );
#								 }
#								 else
#								 {
#										 # TODO: Fixme
#
#										 # I get strange loops then I'm not setting
#										 # switch_req(undef() here. But We should not need
#										 # to to this here. Investigate how to eliminate
#										 # the need for it. switch_req() should be called
#										 # in the specific sections later, where needed.
#
#										 # The problem with switching reqs is that it will
#										 # trigger DB commit which will commit data that
#										 # should be rolled back in case of an error later
#										 # in the request. Arc creations should be made in
#										 # coherent (atomic) groups. Method calls that may
#										 # call yield should not be used in the middle of
#										 # DB work.
#
#										 switch_req(undef);
#										 get_value( $client );
#										 $timeout = TIMEOUT_SHORT; # Get next thing
#								 }
#						 }

			### Do the jobs piled up
			#
			$timeout = TIMEOUT_LONG; # We change this if there are jobs to do
			# List may change during iteration by close_callback...
			my @requests = values %REQUEST;
			foreach my $req ( @requests )
			{
				next unless $req;				# If closed down

				if ( $req->{'cancel'} )
				{
					switch_req( $req );
					debug "cancelled by request";

					# If this was an active request for a master
					# request, it's disconnected state will be
					# detected and another active request will be
					# created.

					# TODO: May be polite to tell the master that this
					# request no longer is of service.

					$req->run_hook('done') unless $req->{'done'};
					$req->{'done'} = 1;
					close_callback($req->{'client'});
				}
				elsif ( $req->{'in_yield'} )
				{
					# Do not do jobs for a request that waits for a child
					debug 3, "In_yield: $req->{reqnum}";
				}
				elsif ( $req->{'wait'} )
				{
					# Waiting for something else to finish...
					debug 3, "$req->{reqnum} stays open, was asked to wait for $req->{'wait'} things";
				}
				elsif ( @{$req->{'jobs'}} )
				{
#				if( ($LEVEL > 3) and ($req->id == $REQNUM ) )
#				{
#			debug "Not doing queued job for req ".$req->id;
#				}
#				else
#				{
					my $job = shift @{$req->{'jobs'}};
					my( $cmd, @args ) = @$job;
					switch_req( $req );
#										 debug(2, sprintf "Found a job %s(%s) in %d", $cmd, join(', ', map {defined $_ ? $_ : '<undef>'} @args ), $req->{reqnum}); ## HEAVY
					$req->$cmd( @args );
#				}
				}
				elsif ( $req->{'childs'} )
				{
					# Stay open while waiting for child
					if ( debug >= 4 )
					{
						debug "$req->{reqnum} stays open, waiting for $req->{'childs'} childs";
						foreach my $child ( values %CHILD )
						{
							my $creq = $child->req;
							my $creqnum = $creq->{'reqnum'};
							my $cclient = client_str($creq->client);
							my $cpid = $child->pid;
							debug "	 Req $creqnum $cclient has a child with pid $cpid";
						}
					}
				}
				else
				{
					# All jobs done for now
					confess "req not a req ".datadump($req) unless ref $req eq 'Para::Frame::Request'; ### DEBUG
					$req->run_hook('done') unless $req->{'done'};
					$req->{'done'} = 1;
					close_callback($req->{'client'}, sprintf "req %s all done", $req->{'reqnum'});
				}

				$timeout = TIMEOUT_SHORT; ### Get the jobs done quick
			}



			### Do background jobs
			#
			if ( add_background_jobs_conditional() )
			{
				$timeout = TIMEOUT_SHORT; # Get next thing
			}


			### Waiting for a child? (*inside* a nested request)
			#
			if ( $child )
			{
				# We will iterate fast in order to catch data from
				# child before the buffer gets full

				# This could be a simple yield and not a child, then just
				# exit now
				return "last" unless ref $child;

				# exit loop if INVOKING child is done
				return "last" if $child->{'done'};
#		return "last" unless $child->{'req'}{'childs'};
			}
			else
			{
				if ( $TERMINATE or $MEMORY )
				{
				TERMINATE_CHECK:
					{
						# Exit asked to and nothing is in flux
						last if keys %REQUEST;
						last if keys %CHILD;
						last if @BGJOBS_PENDING;

						foreach my $s (values %SESSION)
						{
							my $sid = $s->id;
							foreach my $key ( keys %{$s->{'page_result'}} )
							{
								my $result_time =
									$s->{'page_result'}{$key}{'time_done'};

								# will stop trying to serve everything. lesser ambition. Shorter timeout
								if ( $result_time and
										 (time - $result_time > 6) )
								{
									debug "Ignoring stale page result ".
										"from $sid";
									next;
								}

								debug "PAGE RESULT WAITING for $sid";
								last TERMINATE_CHECK;
							}
						}

						if ( $MEMORY and not $TERMINATE )
						{
							debug "MEMORY-initiated HUP";
							$TERMINATE = 'HUP';
						}

						if ( $TERMINATE eq 'HUP' )
						{
							# Make watchdog restart us
							debug "Executing HUP now";
							Para::Frame->go_down;
							exit 1;
						}
						elsif ( $TERMINATE eq 'TERM' )
						{
							# No restart
							debug "Executing TERM now";
							Para::Frame->go_down;
							exit 0;
						}
						elsif ( $TERMINATE eq 'RESTART' )
						{
							debug "Executing RESTART now";
							Para::Frame->restart;
							debug "RESTART FAILED!!!";
						}
						else
						{
							debug "Termination code $TERMINATE not recognized";
							$TERMINATE = 0;
						}
					}
				}
			}

			### Are there any data to be read from childs?	This is
			# only used for childs that will exit after the result are
			# recieved. Worker childs will transmit their result to
			# the server port.
			#
			if ( keys %CHILD )
			{
				# Avoid double deregister
				$SIG{CHLD} = 'IGNORE';
				# TODO: Let the REAPER mark up childs for later processing
				#
				foreach my $child ( values %CHILD )
				{
					my $child_data = '';	# We must init for each child!

					# Do a nonblocking read to get data. We try to read often
					# so that the buffer will not get full.

					$child->{'fh'}->read($child_data, POSIX::BUFSIZ);
					$child->{'data'} .= $child_data;

					if ( $child_data )
					{
						my $cpid = $child->pid;
						my $length = length( $child_data );

						my $tlength = length( $child->{'data'} );

						if ( $child->{'data'} =~ /^(\d{1,8})\0/ )
						{
							# Expected length
							my $elength = length($1)+$1+2;
							if ( $tlength == $elength )
							{
																# Whole string recieved!
								unless ( $child->{'done'} ++ )
								{
									$child->deregister(undef,$1);
									debug "Removing child $cpid";
									kill 9, $cpid;
									delete $CHILD{$cpid};
								}
							}
						}
						else
						{
							debug "Got '$child->{data}'";
						}
					}
				}

				# Now we can turn the signal handling back on
				$SIG{CHLD} = \&Para::Frame::REAPER;

				# See if we got any more signals
				&Para::Frame::REAPER;
			}

		} || 'next';								#default
		if ( $@ )
		{
			my $err = run_error_hooks(catch($@));

			if ( $err->type eq 'cancel' )
			{
				debug "REQUEST CANCELLED\n";
				debug $err->info;
				if ( $REQ and $REQ->{'client'} )
				{
					close_callback($REQ->client);
				}
				undef $REQ;							# In case of contamination
			}
			elsif ( $err->type eq 'action' and
							$err->info =~ /^send: Cannot determine peer address/ )
			{
				debug "LOST CONNECTION";
				if ( $REQ and $REQ->{'client'} )
				{
					cancel_and_close( $REQ, undef, 'lost connection');
				}
				undef $REQ;							# In case of contamination
			}
			else
			{
				warn "# FATAL REQUEST ERROR!!!\n";
				warn "# Unexpected exception:\n";
				warn "#>>\n";
				warn map "#>> $_\n", split /\n/, $err->as_string;
				warn "#>>\n";

				my $emergency_level =
					$Para::Frame::Watchdog::EMERGENCY_DEBUG_LEVEL;
				if ( $Para::Frame::DEBUG < $emergency_level )
				{
					$Para::Frame::DEBUG =
						$Para::Frame::CFG->{'debug'} =
						$emergency_level;
					warn "#Raising global debug to level $Para::Frame::DEBUG\n";
				}
				else
				{
					debug "Make watchdog restart us";
					debug "Executing HUP now";
					Para::Frame->go_down;
					exit 1;
				}

				$timeout = TIMEOUT_SHORT;
			}
		}

		if ( $exit_action eq 'last' )
		{
			last;
		}
	}
	debug(3,"Exiting	main_loop at level $LEVEL",-1);

	if ( $LEVEL )
	{
		$LEVEL --;
	}

	return;
}


##############################################################################

=head2 switch_req

=cut

sub switch_req
{
	# $_[0] => the new $req
	# $_[1] => true if this is a new request

	no warnings 'uninitialized';

	if ( $_[0] ne $REQ )
	{
		# Disabled: ENV is read only. No need to store in both directions. Also,
		# ENV caould have been set before switching REQ...
		#
#				 if ( $REQ )
#				 {
#						 debug "ENVa ".$REQ->{reqnum}." COOKIE: ".$ENV{HTTP_COOKIE};
#						 # Detatch %ENV
#						 $REQ->{'env'} = {%ENV};
#				 }

		Para::Frame->run_hook($REQ, 'before_switch_req', @_);

		if ( $_[0] and not $_[1] )
		{
			if ( $REQ )
			{
				warn sprintf "\n$_[0]->{reqnum} Switching to req (from $REQ->{reqnum})\n", ;
			}
			elsif ( $_[0] ne $REQ_LAST )
			{
				warn sprintf "\n$_[0]->{reqnum} Switching to req\n", ;
			}
		}

#				 unless( ref $_[0] )
#				 {
#						 cluck "REQ nulled";
#				 }

		$U = undef;
		if ( $REQ = $_[0] )
		{
			if ( my $s = $REQ->{'s'} )
			{
				$U	 = $s->u;
				$DEBUG	= $s->{'debug'};
			}

			# Attach %ENV
			%ENV = %{$REQ->{'env'}};
#						 $REQ->{'env'} = \%ENV;
#						 debug "ENVb ".$REQ->{reqnum}." COOKIE: ".$ENV{HTTP_COOKIE};

			$INDENT = $REQ->{'indent'};

			$REQ_LAST = $REQ;					# To remember even then $REQ is undef
		}
		else
		{
			undef %ENV;
		}
	}
}


##############################################################################

=head2 add_client

=cut

sub add_client
{
	my( $client ) = @_;

	# New connection.
	$client = $SERVER->accept;
	if (!$client)
	{
		debug(0,"Problem with accept(): $!");
		return;
	}

	$SELECT->add($client);
	nonblock($client);

#		 debug(1, "New client connected: ".client_str($client));
}


##############################################################################

=head2 get_value

Either we know we have something to read
or we are expecting an answer shortly

Only call this if you KNOW where is a value to get. The answer may not
be the one you were waiting for, so you may have to call this method
several times.

This will also handle incoming data coming AFTER your answer, if there
is any such data to be handled.

In usmmary: It reads all there is and returns

Exceptions: If nothing was gotten before the timeout (5 secs), an
exception will be thrown.

TODO: Cleanup return code...

=cut

sub get_value
{
	confess "DEPRECATED";
#		 my( $client, $level ) = @_;
#
#		 if ( $Para::Frame::FORK )
#		 {
#				 confess "FIXME";
#				 debug(2,"Getting value inside a fork");
#
#				 unless( $Para::Frame::Sender::SOCK )
#				 {
#						 confess "get_value in FORK with no socket";
#				 }
#
#				 while ( $_ = <$Para::Frame::Sender::SOCK> )
#				 {
#						 if ( s/^([\w\-]{3,20})\0// )
#						 {
#								 my $code = $1;
#								 debug(1,"Code $code");
#								 chomp;
#								 if ( $code eq 'RESP' )
#								 {
#										 my $val = $_;
#										 my $aclient = $client;
#										 if ( ref $client eq 'Para::Frame::Request' )
#										 {
#												 $aclient = $client->client;
#
#												 debug(5,"RESP $val ($client->{reqnum}/ $aclient)");
#										 }
#										 else
#										 {
#												 my $req = $REQUEST{ $client };
#												 debug(5,"RESP $val ($req->{reqnum}/$client)");
#										 }
#
#										 push @{$CONN{ $aclient }{RESPONSE}}, $val;
#										 return 1;
#								 }
#								 else
#								 {
#										 die "Unrecognized code: $code\n";
#								 }
#						 }
#						 else
#						 {
#								 die "Unrecognized response: $_\n";
#						 }
#				 }
#
#				 undef $Para::Frame::Sender::SOCK;
#				 debug "get_value return 0 (FORK)";
#				 return 0;
#		 }
#
#
#		 if ( ref $client eq 'Para::Frame::Request' )
#		 {
#				 confess "FIXME";
#
#				 # Probably caled from $req->get_cmd_val()
#				 my $req = $client;
#				 if( $req->{'cancel'} )
#				 {
#						 ## Let caller handle it
#						 debug "get_value return undef";
#						 return undef;
#				 }
#
#				 $client = $req->client;
#				 if ( $client =~ /^background/ )
#				 {
#						 if ( my $areq = $req->{'active_reqest'} )
#						 {
#								 debug 4, "	 Getting value from active_request for $client";
#								 $client = $areq->client;
#								 debug 4, "		 $client";
#						 }
#						 else
#						 {
#								 die "We cant get a value without an active request ($client)\n";
#								 # Unless it's a fork... (handled above)
#						 }
#				 }
#		 }
#
#		 confess "FIXME";
#
#	 HANDLE:
#		 {
#				 fill_buffer($client, $level) or last;
#				 handle_code($client) and redo; # Read more if availible
#		 }
#
#		 debug "get_value return 0 (end)";
#		 return 0;
}


##############################################################################

=head2 recieve_from_clients

=cut

sub recieve_from_clients
{
	my( $timeout ) = @_;

#		 my $DEBUG = Para::Frame::Logging->at_level(5);
	my $DEBUG = 0;

	if ( $DEBUG )
	{
		#### STATUS
		debug "\nCurrent buffers";
		foreach my $oclient ( keys %CONN )
		{
			my $msg = "";
			if ( my $oreq = $REQUEST{ $oclient } )
			{
				$msg .= sprintf "req %3d ", $oreq->{reqnum};
			}

			if ( $CONN{ $oclient }{RESPONSE} )
			{
				$msg .= "RESP ";
			}

			if ( $CONN{$oclient}{INBUFFER} )
			{
				$msg .= length($CONN{$oclient}{INBUFFER});
				if ( my $l = $CONN{ $oclient }{DATALENGTH} )
				{
					$msg .= "/".$l;
				}
			}

			debug "$oclient: $msg";
		}
		debug "\n";
	}

	foreach my $ready ($SELECT->has_exception(0) )
	{
		die "Client $ready has exception (out of bound)";
	}

	my $got_something;

 PROCESS:
	{
		$got_something = 0;

		foreach my $client ($SELECT->can_read( $timeout ) )
		{
			debug "Reading from client $client " if $DEBUG;

			if ( $client == $SERVER )
			{
				# Accept connection even if we should $TERMINATE since
				# it could be communication for finishing existing
				# requests

				debug 1, "New client connected: ".client_str($client) if $DEBUG;
				add_client( $client );
				$got_something ++;
				next;
			}

			unless( $client->connected )
			{
				cancel_and_close( undef, $client, 'lost connection');
				next;
			}

			my $data='';
			undef $!;									# reset error status
			my $rv = $client->recv($data,POSIX::BUFSIZ, 0);

			unless( defined $rv )
			{
				debug sprintf "Error %d while reading from %s: %s", int($!), $client, $! if $DEBUG;
				if ( $IOAGAIN{int $!} ) # Try again (EAGAIN)
				{
					# Try again after trying getting something else
					$got_something++;
					next;
				}

				die "What are we going to do now?";
			}

			unless( length $data )
			{
				#debug "No data from client $client";
				cancel_and_close( undef, $client, 'no data from client');
				next
			}

			$CONN{$client}{INBUFFER} .= $data;
			$CONN{$client}{CLIENT} = $client;
			$got_something ++;
			debug 1, "Adding more data to inbuffer $client" if $DEBUG;
		}

		$timeout = 0;
		last unless $got_something;
	}

	return $got_something;
}

##############################################################################

=head2 handle_recieved_data

=cut

sub handle_recieved_data
{
	my $DEBUG = 0;

	foreach my $client_key ( keys %CONN )
	{
		my $conn = $CONN{$client_key};
		my $client = $conn->{CLIENT};

		next if $conn->{DATALENGTH};
		next unless length $conn->{INBUFFER};

#				 debug(1,"DATALENGTH for $client");
		# Read the length of the data string
		if ( $conn->{INBUFFER} =~ s/^(\d+)\x00// )
		{
			debug(4,"Setting length to $1");
			$conn->{DATALENGTH} = $1;
			next;
		}

		if ( $conn->{INBUFFER} =~ s/^(GET .+\r\n\r\n)/HTTP\x00$1/s )
		{
			### Got an HTTP GET request
			#
			# converting to legacy format

			$conn->{DATALENGTH} = length( $1 ) +5;
			if ( $DEBUG )
			{
				debug 1, "HTTP GET in INBUFFER";
				debug 1, $conn->{INBUFFER}."\n.";
				debug 1, "Setting length to ".$conn->{DATALENGTH};
			}

			next;
		}

		if ( $conn->{INBUFFER} =~ m/^(POST .+?\r\n\r\n)/s )
		{
			### Got an HTTP POST request
			#
			# converting to legacy format

			my $header_length = length( $1 ); # Assume 8-bit

			unless ( $conn->{INBUFFER} =~ /^Content-Length: (\d+)/im )
			{
				debug 0, sprintf "HTTP POST without content-length: %s\n.", $conn->{INBUFFER};
				close_callback($client, "Faulty HTTP POST inbuffer");
				debug "fill_buffer return 0";
				next;
			}

			my $body_length = $1;

			$conn->{INBUFFER} = "HTTP\x00".$conn->{INBUFFER};
			$conn->{DATALENGTH} = $header_length + $body_length + 5;

			if ( $DEBUG )
			{
				debug 1, "HTTP POST in INBUFFER";
				debug 1, $conn->{INBUFFER}."\n.";
				debug 1, "Buffer length is ".length($conn->{INBUFFER});
				debug 1,"Setting length to ".$conn->{DATALENGTH};
			}

			next;
		}

		### UNRECOGNIZED content

		debug 0, sprintf "Strange INBUFFER content: %s\n.", $conn->{INBUFFER};

		debug datadump($REQUEST{ $client },1); ### DEBUG

		close_callback($client, "Faulty inbuffer");
		debug "fill_buffer return 0";
	}


	### EXTRACT MESSAGES
	#
	foreach my $client_key ( keys %CONN )
	{
		my $conn = $CONN{$client_key};
		$conn->{MESSAGE} ||= [];
		next unless $conn->{DATALENGTH};

		my $length_buffer = length( $conn->{INBUFFER}||='' );

		if ( $DEBUG )
		{
			debug "Extract message from client $client_key";
			debug sprintf "	 got %d/%d", $length_buffer, $conn->{DATALENGTH};
		}

		if ( $length_buffer >= $conn->{DATALENGTH} )
		{
			push @{$conn->{MESSAGE}},
				substr( $conn->{INBUFFER}, 0, $conn->{DATALENGTH}, '');
			$conn->{DATALENGTH} = 0;

			if ( $DEBUG )
			{
				debug "	 message length: ".length( $conn->{MESSAGE}[-1] );
				debug "	 inbuffer length: ".length($conn->{INBUFFER});
			}
		}
	}


	###	 PROCESS MESSAGES
	#
	foreach my $client_key ( keys %CONN )
	{
		my $conn = $CONN{$client_key};
		my $client = $conn->{CLIENT} or next;

		# Client still open?
		unless( $client->connected )
		{
			cancel_and_close( undef, $client, 'lost connection');
			next;
		}

		### Assume copy on write... could be a large chunk of data
		while ( my $msg = shift @{$conn->{MESSAGE}} )
		{
			handle_code( $client, \ $msg );

			### Prefere to unwind
			if ( $LEVEL > 50 )			 # Unwinding will sometim es not work...
			{
				debug "UNWINDING At level $LEVEL";
#								 cluck "UNWINDING";
				return;
			}

		}
	}
}


##############################################################################

=head2 fill_buffer DEPRECATED

=cut

sub fill_buffer									# DEPRECATED
{
	confess "DEPRECATED";
#		 my( $client, $level ) = @_;
#
#		 debug 1, "Get value from $client";
#
#		 my $timeout = 5;
#		 $level ||= 0;
#
#	 PROCESS:
#		 {
#
#				 if ( debug >= 1 )								# DEBUG
#				 {
#						 #### STATUS
#						 debug "\nCurrent buffers";
#						 foreach my $oclient ( keys %INBUFFER )
#						 {
#								 my $msg = "";
#								 if ( my $oreq = $REQUEST{ $oclient } )
#								 {
#										 $msg .= sprintf "req %3d ", $oreq->{reqnum};
#								 }
#
#								 if ( $CONN{ $oclient }{RESPONSE} )
#								 {
#										 $msg .= "RESP ";
#								 }
#
#								 $msg .= length($INBUFFER{$oclient});
#
#								 if ( my $l = $DATALENGTH{ $oclient } )
#								 {
#										 $msg .= "/".$l;
#								 }
#
#								 debug "$oclient: $msg";
#						 }
#						 debug "\n";
##						sleep 1;
#				 }
#
#				 debug "Adding to $client" unless exists $INBUFFER{$client}; ### DEBUG
#				 my $length_buffer = length( $INBUFFER{$client}||='' );
#
#				 debug 1, "Length is $length_buffer of ".($DATALENGTH{$client}||'?');
#
#				 unless ( $DATALENGTH{$client} and
#									$length_buffer >= $DATALENGTH{$client} )
#				 {
#						 my $data='';
#						 my $rv = $client->recv($data,POSIX::BUFSIZ, 0);
#
#						 if ( defined $rv and length $data )
#						 {
#								 $INBUFFER{$client} .= $data;
#								 debug 1, "Adding more data to inbuffer $client";
##								debug 0, "Adding: '$data'";
#						 }
#						 elsif ( not length $INBUFFER{$client} )
#						 {
#								 # Client still open?
#								 unless( $client->connected )
#								 {
#										 cancel_and_close( undef, $client, 'lost connection');
#										 return 0;
#								 }
#
#								 if( $! )
#								 {
#										 debug "Error while reading from $client: ".int($!);
#								 }
#
#								 if( $IOAGAIN{int $!} ) # Try again (EAGAIN)
#								 {
#										 # Try again after trying getting something else
#								 }
#								 elsif ( not defined $rv ) # Error during read
#								 {
#										 state $last_lost ||= '';
#
#										 debug "Lost connection to ".client_str($client);
#										 cancel_and_close( undef, $client, 'eof');
#
#										 if ( $last_lost eq $client )
#										 {
##			confess "Double lost connection $client";
#												 cluck "Double lost connection ".client_str($client);
#												 debug "Trying to restart";
#												 $TERMINATE = 'HUP';
#												 die "Lost connection to ".client_str($client);
#										 }
#
#										 $last_lost = $client;
#
#										 return 0;	 # Is this right?
#								 }
#
#								 # Nothing to read yet. Get something else...
#								 return 0 if $level; # unwind
#
#								 my $got_other = 0;
##								my $client_ready = 0;
#								 my $got_data = 0;
#
#								 foreach my $ready ($SELECT->has_exception(0) )
#								 {
#										 debug "Client $ready has exception (out of bound)";
#								 }
#
#								 foreach my $ready ($SELECT->can_read( $timeout ) )
#								 {
#										 unless( $ready->connected )
#										 {
#												 debug "Client $ready not connected";
#										 }
#
#										 if( $ready == $client )
#										 {
#												 debug "fill_buffer (Client ready now)";
#
#												 $rv = $client->recv($data,POSIX::BUFSIZ, 0);
#												 if ( defined $rv and length $data )
#												 {
#														 $INBUFFER{$client} .= $data;
#														 debug 1, "Finally adding more data to inbuffer $client";
#														 $got_data ++;
#														 last;
#												 }
#
##												$client_ready ++;
#												 debug sprintf "	ready or not? (%d / %d / %s) %s", $!, length($data), ($rv?1:0), $!;
#												 next;
#										 }
#
#										 $got_other ++;
#
#
#										 if ( $ready == $SERVER )
#										 {
#												 add_client( $ready );
#												 debug "fill_buffer next (new connection)";
#										 }
#										 else
#										 {
##												$data='';
##												$rv = $ready->recv($data,POSIX::BUFSIZ, 0);
##												if ( defined $rv and length $data )
##												{
##														$INBUFFER{$ready}||='';
##														$INBUFFER{$ready} .= $data;
##														debug 1, "Adding more data to other inbuffer $ready";
##														$data = '';
##														undef $rv;
##
##														$got_other ++;
##												}
##												else
##												{
##														debug "Other client could not read: $!";
##												}
#
#												 my $orig_req = $REQ;
##												my $req = $REQUEST{$ready};
#												 debug 1, "Get new data on level $LEVEL ($level)";
##												debug 2, "Switching req to client ".client_str($ready);
##												switch_req($req);
#												 eval
#												 {
#														 get_value( $ready, $level ++ );
#												 };
#												 switch_req($orig_req);
#												 die $@ if $@;
#
#												 ### Caller will have to call this method again
#												 ### if necessary. This nested request may in
#												 ### turn call the original request, reading
#												 ### the value we wait for here.
#
#												 debug "fill_buffer next (switching)";
#										 }
#								 }
#
#
##								if( $client_ready )
##								{
##										debug "fill_buffer return 0 (client ready)";
##										return 0;
###										 redo;
##								}
#
#								 if( $got_data )
#								 {
#										 # all good
#								 }
#								 elsif( $got_other )
#								 {
#										 debug "fill_buffer return 0 (got other)";
#										 return 0;
#								 }
#								 elsif( $IOAGAIN{int $!} ) # Try again (EAGAIN)
#								 {
#										 debug "fill_buffer redo (EAGAIN)";
#										 return 0; # Now trying again
#								 }
#								 else
#								 {
#										 # No data waiting
#
#										 warn sprintf "Data timeout!!! (%d)", $!;
#
#										 if ( my $req = $REQUEST{$client} )
#										 {
#												 $req->{'timeout_cnt'} ++;
#												 debug 1, $req->logging->debug_data;
#										 }
#
#										 cluck "trace for ".client_str($client);
#
#										 # The caller will have to do the giving up
#
#										 # I have seen that the actual response CAN take
#										 # longer than 5 secs. I don't know why but we
#										 # should let go now and come back in another
#										 # round, if necessary
#
#										 debug "fill_buffer return 0";
#										 return 0;
#
##				throw('action', "Data timeout while talking to client\n");
#								 }
#
#						 }
#						 elsif(	 $DATALENGTH{$client} )
#						 {
#								 debug "============= Waiting for more data?";
#								 debug "	Buffer length: ".length($INBUFFER{$client});
#								 debug "	Datalength: ".$DATALENGTH{$client};
#								 cluck "trace for ".client_str($client);
#
#								 debug "fill_buffer return 0 (more data)";
##								redo;
#								 return 0;
#						 }
#
#						 unless ( $DATALENGTH{$client} )
#						 {
#								 debug(1,"Length of record for $client?");
#								 # Read the length of the data string
#								 if ( $INBUFFER{$client} =~ s/^(\d+)\x00// )
#								 {
#										 debug(4,"Setting length to $1");
#										 $DATALENGTH{$client} = $1;
#								 }
#								 elsif ( $INBUFFER{$client} =~ s/^(GET .+\r\n\r\n)/HTTP\x00$1/s )
#								 {
#										 ### Got an HTTP GET request
#										 #
#										 # converting to legacy format
#
#										 $DATALENGTH{$client} = length( $1 ) +5;
#										 debug 1, "HTTP GET in INBUFFER";
#										 debug 1, "$INBUFFER{$client}\n.";
#										 debug 1,"Setting length to ".$DATALENGTH{$client};
#								 }
#								 elsif ( $INBUFFER{$client} =~ m/^(POST .+?\r\n\r\n)/s )
#								 {
#										 ### Got an HTTP POST request
#
#										 my $header_length = length( $1 ); # Assume 8-bit
#
#										 unless( $INBUFFER{$client} =~ /^Content-Length: (\d+)/im )
#										 {
#												 debug 0, "HTTP POST without content-length: $INBUFFER{$client}\n.";
#												 close_callback($client, "Faulty HTTP POST inbuffer");
#												 debug "fill_buffer return 0";
#												 return 0;
#										 }
#
#										 my $body_length = $1;
#
#										 $INBUFFER{$client} = "HTTP\x00".$INBUFFER{$client};
#										 $DATALENGTH{$client} = $header_length + $body_length + 5;
#
#										 debug 1, "HTTP POST in INBUFFER";
#										 debug 1, "$INBUFFER{$client}\n.";
#										 debug 1, "Buffer length is ".length($INBUFFER{$client});
#										 debug 1,"Setting length to ".$DATALENGTH{$client};
#								 }
#								 else
#								 {
#										 debug 0, "Strange INBUFFER content: $INBUFFER{$client}\n.";
#
#										 debug datadump($REQUEST{ $client },1); ### DEBUG
#
#										 close_callback($client, "Faulty inbuffer");
#										 debug "fill_buffer return 0";
#										 return 0;
#								 }
#						 }
#
#						 # Check if we got a whole record
#						 debug "fill_buffer redo (loop)";
#						 redo;
#				 }
#		 }
#
#		 debug "fill_buffer return 1 (done)";
#		 return 1;
}


##############################################################################

=head2 handle_code

=cut

sub handle_code
{
	my( $client, $msg_ref ) = @_;

	my( $code, $data ) = $$msg_ref =~ m/(\w+)\x00(.*)/s;

	unless ( $code )
	{
		debug(0,"No code given: $$msg_ref");
		close_callback($client,'faulty input');
		return 0;
	}

#		 debug 1, sprintf "GOT code %s (%s)", $code, length($data);
#		 debug 1, "data:\n$data\n.";

	if ( $code eq 'REQ' )
	{
#				 # Skip the req if it's cancelled
#				 #	 As an optimization; Just check the buffer
#				 #
#			 CHECK:
#				 {
#						 if ( length $rest )
#						 {
#								 fill_buffer($client) or last;
#
#								 # Peek in the buffer
#								 if ( $CONN{$client}{INBUFFER} =~ m/^CANCEL\x00/ )
#								 {
#										 # Drop the connection now
#										 warn "SKIPS CANCELLED REQ\n";
#										 close_callback($client);
#										 return 0;
#								 }
#								 # Something else is waitning
#						 }
#				 }

		handle_request( $client, \$data );
		return;
	}

	if ( $code eq 'HTTP' )
	{
		handle_http( $client, $data );
		return;
	}

	if ( $code eq 'CANCEL' )
	{
		my $req = $REQUEST{ $client };
		unless( $req )
		{
			debug "CANCEL from Req not registred: ".client_str($client);
			return;
		}

		$req->cancel;

		# Continue until it's safe to drop the connectio
		# There may be a message sent to client

		# Trying to drop now and let other places handle it
		close_callback( $client, "Cancelled" );
		return;
	}

	if ( $code eq 'RESP' )
	{
		my $req = $REQUEST{ $client };
		debug(5,"RESP $data ($req->{reqnum})");
		push @{$CONN{ $client }{RESPONSE}}, $data;
		return;
	}

	if ( $code eq 'RUN_ACTION' )	# Not interactive
	{
		# Starts action and drops connection.
		# No wait on result

		my $req =
			Para::Frame::Request->
				new_bgrequest("Handling RUN_ACTION (in background)");

		debug 2, "Got val: $data";

		$data =~ s/^(.+?)\?//;
		my $action = $1;
		debug "Action $action";

		my %params;
		foreach my $param ( split '&', $data )
		{
			$param =~ m/^(.*?)=(.*?)$/;
			$params{$1} = $2;
			debug "	 $1 = $2";
		}
#	debug "Running action: $action with params: ". datadump( \%params );
		$req->add_job('run_action', $action, \%params);

#	client_send($client, "9\x00RESP\x00Done");
		close_callback($client, $code); # That's all
		return;
	}

	if ( $code eq 'URI2FILE' )		# CHILD msg
	{
		# redirect request from child to client (via this parent)
		#
		$data =~ s/^(.+?)\x00// or die "Faulty val: $data";
		my $caller_clientaddr = $1;

		debug(2,"URI2FILE($data) recieved");

		# Calling uri2file in the right $REQ
		# Do we need to switch_req() ???

		my $current_req = $REQ;
		my $req = $REQUEST{ $caller_clientaddr } or
			die "Client ".client_str($caller_clientaddr)." not registred";
		my $file = $req->uri2file($data);

		# Send response in calling $REQ
		debug(2,"Returning answer $file");

#	debug "Sending	RESP $file";
		client_send($client, join( "\0", 'RESP', $file ) . "\n" );
		return;
	}

	if ( $code eq 'NOTE' )				# CHILD msg
	{
		# redirect request from child to client (via this parent)
		#
		$data =~ s/^(.+?)\x00// or die "Faulty val: $data";
		my $caller_clientaddr = $1;

		debug(2,"NOTE($data) recieved");

		# Calling uri2file in the right $REQ
		my $current_req = $REQ;

		if ( my $req = $REQUEST{ $caller_clientaddr } )
		{
			$req->note($data);
		}
		else
		{
			# The note may have come from a background request
			debug 0, $data;
		}
		return;
	}

	if ( $code eq 'LOADPAGE' )
	{
		debug(0,"LOADPAGE");
		my $req = $REQUEST{ $client };
		$req->{'in_loadpage'} = 1;
		return;
	}

	if ( $code eq 'PING' )
	{
#				 debug(1,"PING recieved");
#	debug "Sending	PONG";
		client_send($client, "5\x00PONG\x00");
		close_callback($client, $code); # That's all
		return;
	}

	if ( $code eq 'MEMORY' )
	{
		debug(2,"MEMORY recieved");
		my $size = $data;
		$MEMORY = $size;
		Para::Frame->run_hook(undef, 'on_memory', $size);
		return;
	}

	if ( $code eq 'HUP' )
	{
		debug(0,"HUP recieved");
		$TERMINATE = 'HUP';
		return;
	}

	if ( $code eq 'TERM' )
	{
		debug(0,"TERM recieved");
		$TERMINATE = 'TERM';
		return;
	}

	if ( $code eq 'WORKERRESP' )
	{
		local $Storable::Eval = 1;
		my( $caller_id, $result ) = @{thaw($data)};
		my $req;
		if ( $REQ and ($REQ->{reqnum} == $caller_id) )
		{
			$req = $REQ;
		}
		else
		{
			$req = Para::Frame::Request->get_by_id( $caller_id );
		}

		if ( $req )
		{
			unless ( ($req->{'wait'}||0) > 0 )
			{
				die "Req $caller_id not waiting for a result";
			}

			$req->{'workerresp'} = $result;
			$req->{'wait'} --;
			my $worker = delete $req->{'worker'};
			unless ( $worker and $WORKER{ $worker->pid } )
			{
				# See REAPER. Worker may have died
				debug sprintf "Req %d lost a worker", $req->id;
			}
			else
			{
				push @WORKER_IDLE, $worker;
			}
		}
		else
		{
			debug "Req $caller_id no longer exist";
		}

		close_callback($client, $code); # That's all
		return;
	}

	#### UNKNOWN CODE
	#
	debug(0,"(Para::Frame) Strange CODE: $code");
	close_callback($client, "Faulty code");
}


##############################################################################

=head2 nonblock

=cut

sub nonblock
{
	my $socket=shift;

	# Set a socket into nonblocking mode.	 I guess that the 1.18
	# defaulting to autoflush makes this function redundant

	use Fcntl;
	my $flags= fcntl($socket, F_GETFL, 0)
		or die "Can't get flags for socket: $!\n";
	fcntl($socket, F_SETFL, $flags | O_NONBLOCK)
		or die "Can't make socket nonblocking: $!\n";
}


##############################################################################

=head2 cancel_and_close

	cancel_and_close( $req, $client, $reason )

$req may be undef

=cut

sub cancel_and_close
{
	my( $req, $client, $reason ) = @_;

	$req ||= $REQUEST{$client};
	$client ||= $req->{client};

	$req->cancel if $req;
	close_callback( $client, $reason ) if $client;
}


##############################################################################

=head2 close_callback

=cut

sub close_callback
{
	my( $client, $reason ) = @_;

	# Someone disconnected or we want to close the i/o channel.

#		 cluck "Closing connection $client";
#		 unless( ref $client )
#		 {
#				 debug "	not an object";
#		 }

	if ( my $req = $REQUEST{$client} )
	{
		if ( $reason )
		{
			warn sprintf "%d Done in %6.2f secs (%s)\n",
				$req->{reqnum},
				(time - $req->{started}),
				$reason;
		}
		else
		{
			warn sprintf "%d Done in %6.2f secs\n",
				$req->{reqnum},
				(time - $req->{started});
		}

		if ( my $oreq = delete $req->{'original_request'} )
		{
			$oreq->release_subreq($req);
		}

		if ( my $sreqs = $req->{'subrequest'} )
		{
			# Trying to breake reference loops for garbage collecting
			delete $req->{'subrequest'};
			foreach my $sreq ( @{$sreqs} )
			{
				delete $sreq->{'original_request'};
			}
		}

		if ( $client =~ /^background/ )
		{
			#(May be a subrequst, but decoupled)

			# Releasing active request
			delete $req->{'active_reqest'};
			delete $REQUEST{$client};
			delete $CONN{$client};
			switch_req(undef);
			return;
		}
		else
		{
			# Trying to breake reference loops for garbage collecting
			delete $req->{'subrequest'};

		}
	}
	else
	{
		if ( $reason )
		{
			#warn "Client $client done ($reason)\n";
		}
		else
		{
			cluck "Client $client done\n";
		}
	}

	delete $REQUEST{$client};
	delete $CONN{$client};

#		 debug "INBUFFER removed";
#		 debug "Client list now ".join(" / ", keys(%{$CONN{INBUFFER}}));

	switch_req(undef);

	# if not a background request
	if ( ref $client and
			 ( $client != $SERVER )
		 )
	{
		if ( $SELECT->exists( $client ) )
		{
			$SELECT->remove($client);
		}

		if ( $client->connected )
		{
			# I have stopped using this socket
#						 debug "Closing connection";
			$client->shutdown(2) or debug("Failed shutdown: $!");
			$client->close or debug("Failed close: $!");
		}
	}
}


##############################################################################

=head2 REAPER

=cut

sub REAPER
{
	# Taken from example in perl doc

	my $child_pid;
	# If a second child dies while in the signal handler caused by the
	# first death, we won't get another signal. So must loop here else
	# we will leave the unreaped child as a zombie. And the next time
	# two children die we get another zombie. And so on.

#		 warn "| In reaper\n" if $DEBUG > 1;

	while (($child_pid = waitpid(-1, POSIX::WNOHANG)) > 0)
	{
		if ( my $child = delete $CHILD{$child_pid} )
		{
			unless ( $child->{'done'} )
			{
				warn sprintf "| Child %d exited with status %s\n",
					$child_pid, defined $? ? $? : '<undef>';
				$child->deregister( $? );
			}
		}
		elsif ( my $worker = delete $WORKER{$child_pid} )
		{
			warn "| Worker $child_pid exited with status $?\n";
			$worker->deregister( $? );
		}
		else
		{
			warn "| Child $child_pid exited with status $?\n";
			warn "|		No object registerd with PID $child_pid\n";
		}
	}
	$SIG{CHLD} = \&REAPER;				# still loathe sysV
}


##############################################################################

=head2 daemonize

	Para::Frame->daemonize( $run_watchdog )

Starts the paraframe daemon in the background. If C<$run_watchdog> is
true, lets L<Para::Frame::Watchdog> start and watch over the daemon.

=cut

sub daemonize
{
	my( $class, $run_watchdog ) = @_;

	# Detatch AFTER watchdog started sucessfully

	warn "--- daemonize\n";

	my $parent_pid = $$;

	$SIG{CHLD} = sub
	{
		warn "--- Error during daemonize\n";
		Para::Frame->go_down;
		exit 1;
	};
	$SIG{USR1} = sub
	{
#	warn "Running in background\n" if $DEBUG > 3;
		warn "--- Running in background\n";

#	Para::Frame->go_down;
		exit 0;
	};

	my $orig_name = $0;
	$0 = abs_path($0);
	warn "--- $orig_name resolved to $0\n";

	chdir '/'									or die "Can't chdir to /: $!";
	defined(my $pid = fork)		or die "Can't fork: $!";
	if ( $pid )										# In parent
	{
#	open STDIN, '/dev/null'		or die "Can't read /dev/null: $!";
#	open STDOUT, '>/dev/null' or die "Can't write to /dev/null: $!";
		while (1)
		{
			# Waiting for signal from child
			sleep 2;
			warn "--- Waiting for ready signal\n" if $DEBUG > 0;
		}

		warn "--- We should never come here\n";
		Para::Frame->go_down;
		exit;
	}

	# Reset signal handlers for the child
	$SIG{CHLD} = 'IGNORE';
	$SIG{USR1} = 'DEFAULT';

	warn "--- In child\n";

	if ( $run_watchdog )
	{
		Para::Frame::Watchdog->startup(1);
#	open_logfile(); # done in watchdog startup
		POSIX::setsid							or die "Can't start a new session: $!";
		write_pidfile();
#	debug "Signal ready to parent";
		kill 'USR1', $parent_pid;		# Signal parent
		Para::Frame::Watchdog->watch_loop();
	}
	else
	{
		warn "\n\nStarted process $$ on ".now()."\n\n";
		open_logfile();
		Para::Frame->startup();
		POSIX::setsid							or die "Can't start a new session: $!";
		write_pidfile();
		kill 'USR1', $parent_pid;		# Signal parent
		warn "\n\nStarted process $$ on ".now()."\n\n";
		Para::Frame::main_loop();
	}
}


##############################################################################

=head2 restart

	Para::Frame->restart()

Restarts the daemon. We asume that we will restart in the background,
with a watchdog.

TODO: Will try to detect if the process is not a daemon and in that
case restart in the foreground. (Must place new process in same
terminal)

=cut

sub restart
{
	my( $class ) = @_;

	debug "--- In restart";
	Para::Frame->go_down;
	debug "--- executing $0 @ARGV";

	exec("$0 @ARGV"); warn "Exec failed: $!"; sleep 1;
	debug "executing $0";
	exec("$0 @ARGV"); warn "Exec failed: $!";
	debug "failing";
	return 0;
}


##############################################################################

=head2 kill_children

	Para::Frame->kill_children()

=cut

sub kill_children
{
	my( $class ) = @_;

	$SIG{CHLD} = 'IGNORE';				# Not turing it back on!!!
	$SIG{USR1} = 'DEFAULT';

	foreach my $child ( values %CHILD )
	{
		my $cpid = $child->pid;
		debug "	 killing child $cpid";
		kill 9, $cpid;
	}

	foreach my $child ( values %WORKER )
	{
		my $cpid = $child->pid;
		debug "	 killing worker $cpid";
		kill 9, $cpid;
	}

}


##############################################################################

=head2 go_down

	Para::Frame->go_down()

Assumes that we will exit one way or another after this. Thus, we will
shut down the signal handling before killing the childs, and NOT turn
it on afterwards.

=cut

sub go_down
{
	my( $class ) = @_;

	$SERVER and $SERVER->close();

	debug "Cleaning up";
	print "DOWN\n";


	open STDOUT, '>/dev/null' or die "Can't write to /dev/null: $!";

	Para::Frame->kill_children;

	if( $ARGV[0] eq 'no_watchdog' ){
		exit 1;
	}
	return 1;
}


##############################################################################

=head2 add_background_jobs_conditional

=cut

sub add_background_jobs_conditional
{
	debug(4,"add_background_jobs_conditional");
	# Add background jobs to do unless the load is too high, unless we
	# waited too long anyway

	return if $LEVEL;							# No bgjob if nested in req


	# Return it hasn't passed BGJOB_MAX secs since last time
	my $last_time = $BGJOBDATE ||= time;
	my $delta = time - $last_time;

	if ( $MEMORY or $TERMINATE )
	{
		# Clear out existing jobs if we want to reload
	}
	elsif ( $delta < BGJOB_MAX )
	{
		debug(4,"Too few seconds for MAX: $delta < ". BGJOB_MAX);
		return;
	}

	# Cache cleanup could safely be done here
	# But nothing that requires a $req
	Para::Frame->run_hook(undef, 'busy_background_job', $delta);

	# Do background jobs if no req jobs waiting
	#
	return if values %REQUEST;

	# Expire old page results and sessions
	#
	foreach my $s (values %SESSION)
	{
		my $sid = $s->id;
		if ( time - $s->latest->epoch > 2*60*60 )
		{
			debug "Expired old session $sid";
			delete $SESSION{$sid};
			next;
		}

		foreach my $key ( keys %{$s->{'page_result'}} )
		{
			my $result_time =
				$s->{'page_result'}{$key}{'time_done'};

			if ( $result_time and (time - $result_time > 240) )
			{
				debug "Expired page result from $sid: $key";
				delete $s->{'page_result'}{$key};
			}
		}
	}


	if ( not $CFG->{'do_bgjob'} )
	{
		debug(3,"Not configged to do bgjobs");
		while ( my $job = shift @BGJOBS_PENDING )
		{
			my( $oreq, $label, $coderef, @args ) = @$job;
			debug "Clearing out job $label from req $oreq->{reqnum}".
				(@args?" with args @args":'');
		}
		return;
	}

	my $sysload;

	# Clear out existing jobs if we want to reload
	if ( @BGJOBS_PENDING and ( $MEMORY or $TERMINATE ) )
	{
		return add_background_jobs($delta, $sysload);
	}

	# Return if CPU load is over BGJOB_CPU
	if ( $delta < BGJOB_MIN )			# unless a long time has passed
	{
		$sysload = (Sys::CpuLoad::load)[1];
		debug(3,"Sysload too high. $sysload > ". BGJOB_CPU)
			if $sysload > BGJOB_CPU;
		return if $sysload > BGJOB_CPU;
	}

	# Return if we had no visitors unless BGJOB_MED secs passed
	$BGJOBNR ||= -1;
	if ( $BGJOBNR == $REQNUM )
	{
		debug(4,"Not enough seconds passed. $delta < ". BGJOB_MED)
			if $delta < BGJOB_MED;
		return if $delta < BGJOB_MED;
	}

	### Reload updated modules
	Para::Frame::Reload->check_for_updates;

	return add_background_jobs($delta, $sysload);
}


##############################################################################

=head2 add_background_jobs

RUNS bgjobs!

=cut

sub add_background_jobs
{
	debug(3,"add_background_jobs");
	my( $delta, $sysload ) = @_;

	my $req = Para::Frame::Request->new_bgrequest();


	my $bg_user;
	my $user_class = $Para::Frame::CFG->{'user_class'};

	# Make sure the user is the same for all jobs in a request

	# Add pending jobs set up with $req->add_background_job
	#
	if ( @BGJOBS_PENDING )
	{
		debug(3,"There are BGJOBS_PENDING");
		my $job = shift @BGJOBS_PENDING;
		my $original_request = shift @$job;
		my $reqnum = $original_request->{'reqnum'};
		$bg_user = $original_request->session->u;
		$user_class->change_current_user($bg_user);

		# Make sure the original request is the same for all jobs in
		# each background request

		$req->{'original_request'} = $original_request;
		$req->set_site($original_request->site);
		$req->add_job('run_code', @$job);

		for ( my $i=0; $i<=$#BGJOBS_PENDING; $i++ )
		{
			if ( $BGJOBS_PENDING[$i][0]{'reqnum'} == $reqnum )
			{
				my $job = splice @BGJOBS_PENDING, $i, 1;
				shift @$job;
				$req->add_job('run_code', @$job);

				# This may have been the last item in the list
				$i--;
			}
		}
	}
	elsif ( not $TERMINATE and not $MEMORY )
	{
		### Debug info
		if ( debug > 2 )
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
	$BGJOBNR	 = $REQNUM;

	return 1;
}


##############################################################################

=head2 handle_request

=cut

sub handle_request
{
	my( $client, $recordref ) = @_;

	$REQNUM ++;
	warn "\n\n$REQNUM Handling new request\n";
#		 warn "client $client\n"; ### DEBUG

	### Reload updated modules
	Para::Frame::Reload->check_for_updates;

	### Create request ($REQ not yet set)
	my $req = Para::Frame::Request->new( $REQNUM, $client, $recordref );
	### Register the request
	$REQUEST{ $client } = $req;
	$CONN{ $client }{RESPONSE} = []; ### Client response queue
	switch_req( $req, 1 );

	#################

	$req->init or do
	{
		debug "Ignoring this request";
		close_callback($req->{'client'});
		return;
	};

	my $session = $req->session;


 RESPONSE:
	{
		### Redirected from another page?
#	my $key = $req->original_url_string;
		my $key = $req->{'env'}{'REQUEST_URI'}
			|| $req->original_url_string;
#warn "req key is $key\n";
		if ( $session->{'page_result'}{ $key } )
		{
			$req->send_stored_result( $key );
		}
		else
		{

			# Authenticate user identity
			my $user_class = $Para::Frame::CFG->{'user_class'};
			$user_class->identify_user; # Will set $s->{user}
			$user_class->authenticate_user;

			### Debug info
			my $t = now();
			warn sprintf("# %s %s - %s\n# Sid %s - %d - Uid %d - debug %d\n",
									 $t->ymd,
									 $t->hms('.'),
									 $req->client_ip,
									 $session->id,
									 $session->count,
									 $session->u->id,
									 $session->{'debug'},
									);
			warn "# ".client_str($client)."\n" if debug() > 4;

			my $query_string = $req->q->query_string();
			$query_string =~ s/(passw(or)?d[^=;]*)=[^;]+/$1=*****/g;
			warn "# $query_string\n"; ### Verbose

			$req->setup_jobs;
			$req->reset_response;			# Needs lang and jobs
			my $resp = $req->response;
			$req->run_hook('on_first_response', $resp);
			$session->route->init;

			if ( my $client_time = $req->http_if_modified_since )
			{
				if ( my $mtime = $resp->last_modified )
				{
					if ( $mtime <= $client_time )
					{
						$resp->send_not_modified;
						$req->done;
						last RESPONSE;
					}
				}
			}


			# TODO: Do not use loadpage for non-html mimetypes
			#				... Client side will only use it for text/html

			# Do not send loadpage if we didn't got a session object

			# Do not send loadpage if $TERMINATE active

			my $loadpage = $req->dirconfig->{'loadpage'} ||
				$req->site->loadpage;
			if ( $session->count )
			{
				if ( ($loadpage ne 'no') and not $TERMINATE )
				{
					$req->send_code('USE_LOADPAGE', $loadpage, 3, $REQNUM,
													loc("Processing"));
				}
			}
			else
			{
				# We must deliver the session cookie. It is needed by
				# future loadpages!

				debug "This is the first request in this session";
			}



			### queue request if we are nested in yield
			if ( $LEVEL )
			{
				debug "Queueing job for ".$req->id;
				$req->add_job('nop');
				$req->add_job('after_jobs');
			}
			else
			{
				$req->after_jobs;
			}
		}
	}

	### Clean up used globals
}


##############################################################################

=head2 handle_http

=cut

sub handle_http
{
	my( $client, $message ) = @_;

	$REQNUM ++;
	warn "\n\n$REQNUM Handling new HTTP request\n";

	### Reload updated modules
	Para::Frame::Reload->check_for_updates;

	### Create request ($REQ not yet set)
	my $req = Para::Frame::Request->new_minimal( $REQNUM, $client );

	### Register the request
	$REQUEST{ $client } = $req;
	$CONN{ $client }{RESPONSE} = []; ### Client response queue
	switch_req( $req, 1 );

	#################

	$req->http_init( $message );
	my $session = $req->session;

	### Debug info
	my $t = now();
	warn sprintf("# %s %s - %s\n# Sid %s - %d - Uid %d - debug %d\n",
							 $t->ymd,
							 $t->hms('.'),
							 $req->client_ip,
							 $session->id,
							 $session->count,
							 $session->u->id,
							 $session->{'debug'},
							);
	warn "# ".client_str($client)."\n" if debug() > 4;

#			$req->setup_jobs;
#			$req->reset_response; # Needs lang and jobs
#			$req->run_hook('on_first_response', $resp);
#			$session->route->init;

	my $resp = $req->response;
	if ( $resp->render_output() )
	{
		$resp->send_http_output();
	}
	debug "Error: $@" if $@;

	return $req->done;
}


##############################################################################

=head2 add_hook

	Para::Frame->add_hook( $label, \&code )

Adds code to be run on special occations. This adds the code to the
hook. The actual hook is added (created) by adding the hook label to
%HOOK and then run the hook using L</run_hook>.

Availible hooks are:

=head3 on_configure

Runs just after the main PF configure. Before DB connection. Before startup.

=head3 on_startup

Runs just before the C<main_loop>.

=head3 on_memory

Runs then the watchdog send a C<MEMORY> notice.

=head3 on_error_detect

Runs then the exception is catched by
L<Para::Frame::Result/exception>.

=head3 on_fork

Runs in the child just after the fork.

=head3 on_reload

Called with filepath as argument on each reload of a module. Will also
be called on first load of module if loaded by compile() method.

=head3 done

Runs just before the request is done.

=head3 before_user_login

Runs before user logged in, in L<Para::Frame::Action::user_login>

=head3 user_login

Runs after user logged in, in L<Para::Frame::Action::user_login>

=head3 before_user_logout

Runs after user logged out, in L<Para::Frame::User/logout>

=head3 after_db_connect

Runs after each DB connect from L<Para::Frame::DBIx/connect>

=head3 before_db_commit

Runs before committing each DB, from L<Para::Frame::DBIx/commit>

=head3 after_db_rollback

Runs after a rollback for each DB, from L<Para::Frame::DBIx/rollback>

=head3 before_switch_req

Runs just before switching from one request to another. Not Switching
from one request to another can be done several times before the
request is done.

=head3 before_render_output

Runs before the result page starts to render.

=head3 busy_background_job

Runs often, between requests.

=head3 add_background_jobs

For adding jobs that should be done in the background, when there is
nothing else to do or when it hasen't run in a while.

=cut

sub add_hook
{
	my( $class, $label, $code ) = @_;

	debug(4,"add_hook $label from ".(caller));

	# Validate hook label
	unless ( ref $HOOK{$label} )
	{
		die "No such hook: $label\n";
	}

	push @{$HOOK{$label}}, $code;
}


##############################################################################

=head2 run_hook

Para::Frame->run_hook( $req, $label );

Runs hooks with label $label.

=cut

sub run_hook
{
	my( $class, $req, $label ) = (shift, shift, shift);
	if ( debug > 3 )
#		 if( debug )
	{
		unless( $label )
		{
			carp "Hook label missing";
		}

		if ( $req and $req->{reqnum} )
		{
			debug(0,"run_hook $label for $req->{reqnum}");
		}
		else
		{
			debug(0,"run_hook $label");
		}
	}

	return unless $HOOK{$label};

	my %running = ();							# Stop on recursive running

	my $hooks = $HOOK{$label};
	$hooks = [$hooks] unless ref $hooks eq 'ARRAY';
	foreach my $hook (@$hooks)
	{
		if ( $Para::Frame::hooks_running{"$hook"} )
		{
			warn "Avoided running $label hook $hook again\n";
		}
		else
		{
			$Para::Frame::hooks_running{"$hook"} ++;
			switch_req( $req ) if $req;
#			warn "about to run coderef $hook with params @_"; ## DEBUG
			eval
			{
				my $val = &{$hook}(@_);
			};
			$Para::Frame::hooks_running{"$hook"} --;
			if ( $@ )
			{
				debug(3, "hook $label throw an exception".datadump($@));
				die $@;
			}
		}
	}

	debug(4,"run_hook $label - done");
	return 1;
}


##############################################################################

=head2 add_global_tt_params

	Para::Frame->add_global_tt_params( \%params )

Adds all params to the global params to be used for all
templates. Replacing existing params if the name is the same.

=cut

sub add_global_tt_params
{
	my( $class, $params ) = @_;

	while ( my($key, $val) = each %$params )
	{
		$PARAMS->{$key} = $val;
#	cluck("Add global TT param $key from ");
	}
}


##############################################################################

=head2 do_hup

Will tell watchdog to restart server by forking.

=cut

sub do_hup
{
	$TERMINATE = 'HUP';
}


##############################################################################

=head2 write_pidfile

=cut

sub write_pidfile
{
	my( $pid ) = @_;
	$pid ||= $$;
	my $pidfile = $Para::Frame::CFG->{'pidfile'};
#		 warn "Writing pidfile: $pidfile\n";
	create_file( $pidfile, "$pid\n",
							 {
								do_not_chmod_dir => 1,
							 });
	$ACTIVE_PIDFILE = $pid;
}


##############################################################################

=head2 remove_pidfile

=cut

sub remove_pidfile
{
	my $pidfile = $Para::Frame::CFG->{'pidfile'};
	unlink $pidfile or warn "Failed to remove $pidfile: $!\n";
}


##############################################################################

=head2 END

=cut

END
{
	if ( $ACTIVE_PIDFILE and $ACTIVE_PIDFILE == $$ )
	{
		remove_pidfile();
		undef $ACTIVE_PIDFILE;
	}
}


##############################################################################

=head2 open_logfile

See also L<Para::Frame::Watchdog/open_logfile>

=cut

sub open_logfile
{
	my $log = $CFG->{'logfile'};
	my $logdir = dirname $log;
	create_dir($logdir, 0770);

	open STDOUT, '>>', $log		or die "Can't append to $log: $!";
	open STDERR, '>&STDOUT'		or die "Can't dup stdout: $!";
	binmode(STDOUT, ":utf8");
	binmode(STDERR, ":utf8");

	chmod_file($log);
}


##############################################################################

=head2 configure

	Para::Frame->configure( \%cfg )

Configures paraframe before startup. The configuration is stored in
C<$Para::Frame::CFG>

These configuration params are used:


=head3 appback

This is a listref of server paths. Each path should bee a dir that
holds a C<html> dir, or a C<dev> dir, for compiled sites.	 See
L<Para::Frame::Site/appback>.

Must be defined


=head3 appbase

A string that gives the base part of the package name for actions.

Must be defined

Example: If you set appbase to C<My::App>, the action C<my_action>
will be looked for as L<My::App::Action::my_action>.


=head3 appfmly

This should be a listref of elements, each to be treated as fallbacks
for L<Para::Frame::Site/appbase>.	 If no actions are found under
L<Para::Frame::Site/appbase> one after one of the elements in
C<appfmly> are tried. See L<Para::Frame::Site/appfmly>.

Defaults to none.


=head3 approot

The path to application. This is the dir that holds the C<lib> and
possibly the C<var> dirs. See L<Para::Frame::Site/approot>.

Must be defined


=head3 bg_user_code

A coderef that generates a user object to be used for background jobs.

Defaults to code that C<get> C<guest> from L</user_class>.


=head3 debug

Sets global C<$Para::Frame::DEBUG> value that will be used as default
debug value for all sessions.

Default is 0.


=head3 dir_log

The dir to store the paraframe log.

Default is C<$dir_var/log>


=head3 dir_run

The dir to store the process pid.

Default is C<$dir_var/run>


=head3 dir_var

The base for L</dir_log> and L</dir_run> and L</ttcdir>.

Default is C</var>


=head3 l10n_class

The class to use for localizations. Should be a subclass to
L<Para::Frame::L10N>.

Defaults to C<Para::Frame::L10N>


=head3 languages

A ref to an array of scalar two letter strings of the language codes
the sites supports. This config will be the default if no list is
given to the specific site. See L<Para::Frame::Site/languages>.


=head3 locale

Specifies what to set LC_ALL to, except LC_NUMERIC that is set to
C.	The default is sv_SE.


=head3 logfile

The file to use for logging.

Defaults to L</dir_log> followed by C</parframe_$port.log>


=head3 paraframe

The dir that holds paraframe.

Default is C</usr/local/paraframe>


=head3 paraframe_group

The file group to set files to that are created.

Default is C<staff>


=head3 pidfile

The file to use for storing the paraframe pid.

Defaults to L</dir_run> followed by C</parframe_$port.pid>


=head3 port

The port top listen on for incoming requests.

Defaults to C<7788>.


=head3 session_class

The class to use for sessions. Should be a subclass to
L<Para::Frame::Session>.

Defaults to C<Para::Frame::Session>


=head3 site_auto

If true, accepts hosts in request even if no matching site has been
created.	See L<Para::Frame::Site/get_by_req>. C<site_auto> can also
be the name of a site to use for the template site.


=head3 site_autodetect

... document this


=head3 site_class

The class to use for representing sites.	Should be a subclass to
L<Para::Frame::Site>.

Defaults to C<Para::Frame::Site>


=head3 th

C<th> is a ref to a hash of L<Para::Frame::Burner> objects. You should
use the default configuration.

There are three standard burners.

	html		 = The burner used for all tt pages

	plain		 = The burner used for emails and other plain text things

	html_pre = The burner for precompiling of tt pages

Example for adding a filter to the html burner:

	Para::Frame::Burner->get_by_type('html')->add_filters({
			'upper_case' => sub{ return uc($_[0]) },
	});

See also L<Para::Frame::Burner>


=head3 time_zone

Sets the time zone for L<Para::Frame::Time>.

Defaults to C<local>


=head3 time_format

Sets the default presentation of times using
L<Para::Frame::Time/format_datetime>

Defaults to C<%Y-%m-%d %H.%M>


=head3 time_stringify

Calls L<Para::Frame::Time/set_stringify> with the param.


=head3 tt_plugins

Adds a list of L<Template::Plugin> bases. Always adds
L<Para::Frame::Template::Plugin>.

Defaults to the empty list.

=head3 tt_plugin_loaders

Adds a list of TT plugin loaders. Always adds L<Template::Plugins> and
gives it C<tt_plugins>

=head3 ttcdir

The directory that holds the compiled templates.

Defaults to L</dir_var/ttc> or L</appback/var/ttc> or
L</approot/var/ttc> followed by C</var/ttc>.


=head3 umask

The default umask for created files.

Defaults C<0007>


=head3 user_class

The class to use for user identification. Should be a subclass to
L<Para::Frame::User>.

Defaults to C<Para::Frame::User>


=head3 worker_startup

The number of workers to spawn during startup. The sooner a worker is
spawned, the less memory will it use. The workers lives on til the
next server HUP.	More workes will spawn on demand.

Defaults to C<0>


=cut

sub configure
{
	my( $class, $cfg_in ) = @_;

	$cfg_in or die "No configuration given\n";

	# Init global variables
	#
	$REQNUM			= 0;
	$CFG				= {};
	$PARAMS			= {};
	$INDENT			= 0;

	$CFG = $cfg_in;								# Assign to global var
#		 debug( datadump( $Para::Frame::CFG ) ); ### DEBUG

	$ENV{PATH} = "/usr/bin:/bin";

	# Init locale
	$CFG->{'locale'} ||= "sv_SE.UTF8";
	setlocale(LC_ALL, $CFG->{'locale'});
	setlocale(LC_NUMERIC, "C");

	### Set main debug level
	$DEBUG = $CFG->{'debug'} || 0;

	$CFG->{'dir_var'} ||= '/var';
	$CFG->{'dir_log'} ||= $CFG->{'dir_var'}."/log";
	$CFG->{'dir_run'} ||= $CFG->{'dir_var'}."/run";
	$CFG->{'dir_tmp'} ||= $CFG->{'dir_var'}."/tmp";

	$CFG->{'paraframe'} ||= '/usr/local/paraframe';

	$CFG->{'paraframe_group'} ||= 'staff';
	getgrnam( $CFG->{'paraframe_group'} )
		or die "paraframe_group $CFG->{paraframe_group} doesn't exist\n";

	$CFG->{'approot'} || $CFG->{'appback'}
		or die "appback or approot missing in config\n";

	$CFG->{'appbase'}
		or die "appbase missing in config\n";

	# $Para::Frame::Time::TZ is set at startup from:
	#
	$CFG->{'time_zone'} ||= "local";
	Para::Frame::Time->set_timezone($CFG->{'time_zone'});

	$CFG->{'time_format'} ||= "%Y-%m-%d %H.%M";
	$Para::Frame::Time::FORMAT = DateTime::Format::Strptime->
		new(
				pattern => $CFG->{'time_format'},
				time_zone => $Para::Frame::Time::TZ,
				locale => $CFG->{'locale'},
			 );

	$CFG->{'time_stringify'} ||= 0;
	Para::Frame::Time->set_stringify($CFG->{'time_stringify'});

	$CFG->{'umask'} ||= 0007;
	umask($CFG->{'umask'});


	# Make appfmly and appback listrefs if they are not
	foreach my $key ('appfmly', 'appback')
	{
		unless ( ref $CFG->{$key} )
		{
			my @content = $CFG->{$key} ? $CFG->{$key} : ();
			$CFG->{$key} = [ @content ];
		}

		if ( $DEBUG > 3 )
		{
			warn "$key set to ".datadump($CFG->{$key});
		}
	}

	my $ttcbase = $CFG->{'dir_var'} || ($CFG->{'appback'}[0]?$CFG->{'appback'}[0] .'/var':
																			$CFG->{'approot'} .'/var');
	$CFG->{'ttcdir'} ||= $ttcbase . "/ttc";
	debug 2, "ttcdir set to ".$CFG->{'ttcdir'};

	my $tt_plugins = $CFG->{'tt_plugins'} || [];
	$tt_plugins = [$tt_plugins] unless ref $tt_plugins;
	push @$tt_plugins, 'Para::Frame::Template::Plugin';

	my $tt_plugin_loaders = $CFG->{'tt_plugin_loaders'} || [];
	unless( UNIVERSAL::isa $tt_plugin_loaders, 'ARRAY' )
	{
		$tt_plugin_loaders = [$tt_plugin_loaders];
	}
	use Template::Plugins;
	push @$tt_plugin_loaders,
		Template::Plugins->new({PLUGIN_BASE => $tt_plugins});

	### Add custom VMethods
	use Template::Stash;
	my $number_format = Number::Format->new
		(
		 DECIMAL_DIGITS => 0,
		 THOUSANDS_SEP => ' ',
		);
	$Template::Stash::SCALAR_OPS->{ format_number } = sub {
		return $number_format->format_number(shift);
	};


	my %th_default =
		(
		 ENCODING => 'utf8',
		 PRE_PROCESS => 'header_prepare.tt',
		 POST_PROCESS => 'footer_prepare.tt',
#	 STASH => Para::Frame::Template::Stash::CheckUTF8->new,
		 TRIM => 1,
		 PRE_CHOMP => 1,
		 POST_CHOMP => 1,
		 RECURSION => 1,
		 LOAD_PLUGINS => $tt_plugin_loaders,
#	 PLUGIN_BASE => $tt_plugins,
		 ABSOLUTE => 1,
#					DEBUG_ALL => 1,	 # DEBUG
		 FILTERS =>
		 {
#			 loc => \&Para::Frame::L10N::loc,
			'esc_apostrophe' => sub { $_[0] =~ s/'/\\'/g; $_[0] },
		 },
		);


	Para::Frame::Burner->add({
														%th_default,
														INTERPOLATE => 1,
														COMPILE_DIR =>	$CFG->{'ttcdir'}.'/html',
														type => 'html',
														subdir_suffix => '',
														pre_dir => 'inc',
														inc_dir => 'inc',
														handles => ['tt', 'html_tt', 'xtt'],
													 });



	Para::Frame::Burner->add({
														%th_default,
														COMPILE_DIR =>	$CFG->{'ttcdir'}.'/html_pre',
														TAG_STYLE => 'star',
														type => 'html_pre',
														subdir_suffix => '_pre',
														pre_dir => 'inc_pre',
														inc_dir => 'inc',
													 });

	Para::Frame::Burner->add({
#						STASH => Para::Frame::Template::Stash::CheckUTF8->new,
														COMPILE_DIR => $CFG->{'ttcdir'}.'/plain',
														FILTERS =>
														{
														 'uri' => sub { CGI::escape($_[0]) },
														 'lf'	 => sub { $_[0] =~ s/\r\n/\n/g; $_[0] },
														 'autoformat' => sub { autoformat($_[0]) },
														 'esc_apostrophe' => sub { $_[0] =~ s/'/\\'/g; $_[0] },
														},
														type => 'plain',
														subdir_suffix => '_plain',
														pre_dir => 'inc_plain',
														inc_dir => 'inc_plain',
														handles => ['css_tt','js_tt','css_dtt','js_dtt'],
														ABSOLUTE => 1,
														STRICT => 1,
														DEBUG => 'undef',
														TRIM => 1,
													 });

	$CFG->{'port'} ||= 7788;

	$CFG->{'pidfile'} ||= $CFG->{'dir_run'} .
		"/parframe_" . $CFG->{'port'} . ".pid";
	$CFG->{'logfile'} ||= $CFG->{'dir_log'} .
		"/paraframe_" . $CFG->{'port'} . ".log";

	$CFG->{'user_class'} ||= 'Para::Frame::User';
	$CFG->{'site_class'} ||= 'Para::Frame::Site';
	$CFG->{'session_class'} ||= 'Para::Frame::Session';
	$CFG->{'l10n_class'} ||= 'Para::Frame::L10N';

	$CFG->{'bg_user_code'} ||= sub{ $CFG->{'user_class'}->get('root') };

	$CFG->{'worker_startup'} ||= 0;

	$class->set_global_tt_params;

	# Configure other classes
	#
	Para::Frame::Route->on_configure;
	Para::Frame::Widget->on_configure;
	Para::Frame::Email::Address->on_configure;

	# Making the version availible
	$CFG->{'version'} = $Para::Frame::VERSION;
}


##############################################################################

=head2 Session

	Para::Frame->Session

Returns the L</session_class> string.

=cut

sub Session
{
	$CFG->{'session_class'};
}


##############################################################################

=head2 User

	Para::Frame->User

Returns the L</user_class> string.

=cut

sub User
{
	$CFG->{'user_class'};
}


##############################################################################

=head2 dir

Returns the L</paraframe> dir.

=cut

sub dir
{
	return $CFG->{'paraframe'};
}


##############################################################################

=head2 report

Returns a report in plain text of server status

=cut

sub report
{
	my $out = "SERVER REPORT\n\n";
	$out .= sprintf "The time is %s\n", now->strftime("%F %H.%M.%S");
#		 $out .= "SERVER obj: $SERVER\n";
	$out .= "Global DEBUG level: $DEBUG\n";
	$out .= "DEBUG indent: $INDENT\n";
	$out .= "Current requst is $REQ->{'reqnum'}\n" if $REQ;
	$out .= "Level is $LEVEL\n";
	$out .= "Terminate is $TERMINATE\n";
#		 $out .= "Last running request was $REQ_LAST->{'reqnum'}\n";
	$out .= sprintf "Current user is %s\n", $U->name;
	$out .= "\nActive requests:\n";

	foreach my $reqkey (keys %REQUEST)
	{
		my $req = $REQUEST{$reqkey};
		my $reqnum = $req->{'reqnum'};
		$out .= "Req $reqnum\n";

		if ( $req->{'in_yield'} )
		{
			$out .= "	 In_yield\n";
		}

		if ( $req->{'cancel'} )
		{
			$out .=	 "	cancelled by request\n";
		}

		if ( $req->{'wait'} )
		{
			$out .= "	 stays open, was asked to wait for $req->{'wait'} things\n";
		}

		if ( my $numjobs = @{$req->{'jobs'}} )
		{
			$out .= "	 $numjobs jobs:\n";
			foreach my $job (@{$req->{'jobs'}})
			{
				my( $cmd, @args ) = @$job;
				$out .= "		 job $cmd with args @args\n";
			}
		}

		if ( $req->{'childs'} )
		{
			$out .= "	 stays open, waiting for $req->{'childs'} childs\n";
		}
	}

	$out .= "\nChilds:\n";
	foreach my $child ( values %CHILD )
	{
		my $creq = $child->req;
		my $creqnum = $creq->{'reqnum'};
		my $cclient = client_str($creq->client);
		my $cpid = $child->pid;
		$out .= "	 Req $creqnum $cclient has a child with pid $cpid\n";
	}
	unless( keys %CHILD )
	{
		$out .= "none\n";
	}

	$out .= "\n";

	if ( $BGJOBDATE )
	{
		$out .= sprintf "Last background job (#%d) was done %s\n",
			$BGJOBNR, Para::Frame::Time->get($BGJOBDATE)->
			strftime("%F %H.%M.%S");
	}

	$out .= "\nActive background jobs:\n";
	foreach my $job ( @BGJOBS_PENDING )
	{
		my( $oreq, $label, $coderef, @args ) = @$job;
		$out .= "Original req $oreq->{reqnum}\n";
		$out .= "	 Code $label with args @args\n"
	}
	unless( @BGJOBS_PENDING )
	{
		$out .= "none\n";
	}

	$out .= "\n";

	$out .= "Shortest interval between BG jobs: @{[BGJOB_MAX]} secs\n";
	$out .= "Longest	interval between BG jobs: @{[BGJOB_MIN]} secs\n";

	$out .= "\n";

	$out .= longmess();


	return $out;
}


##############################################################################

=head2 flag_restart

	Para::Frame->flag_restart()

=cut

sub flag_restart
{
	$Para::Frame::TERMINATE = 'RESTART';
}


##############################################################################

=head2 set_global_tt_params

The standard functions availible in templates.

Most of them exists in both from client and not client.

=over

=item cfg

$app->conf : L<Para::Frame/configure>

=item debug

Emit a debug message in the error log. See L<Para::Frame::Utils/debug>

=item dump

The L<Para::Frame::Utils/datadump> function.	To be used for
debugging. Either dump the data structure inside the page (in
<pre></pre>) or combine with debug to send the dump to the error
log. For example: [% debug(dump(myvar)) %]

=item emergency_mode

True if paraframe recovered from an abnormal error.

=item file

Calls L<Para::Frame::File/new> with the given params

=item loc

Calls L<Para::Frame::L10N/loc> with the given params

=item locescape

Calls L<Para::Frame::L10N/locescape> with the given params

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

See also L<Para::Frame::Widget> and
L<Para::Frame::Renderer::TT/set_tt_params>

=cut

sub set_global_tt_params
{
	my( $class ) = @_;

	my $params =
	{
	 'cfg'						 => $Para::Frame::CFG,
	 'debug'					 => sub{ debug(@_);"" },
	 'debug_level'		 => sub{ $Para::Frame::DEBUG },
	 'dump'						 => \&Para::Frame::Utils::datadump,
	 'emergency_mode'	 => sub{ $Para::Frame::Watchdog::EMERGENCY_MODE },
	 'file'						 => sub{Para::Frame::File->new(@_)},
	 'loc'						 => \&Para::Frame::L10N::loc,
	 'locescape'			 => \&Para::Frame::L10N::locescape,
	 'mt'							 => \&Para::Frame::L10N::mt,
	 'note'						 => sub{ $Para::Frame::REQ->note(@_); "" },
	 'rand'						 => sub{ int rand($_[0]) },
	 'timediff'				 => \&Para::Frame::Utils::timediff,
	 'uri'						 => \&Para::Frame::Utils::uri,
	 'uri_path'				 => \&Para::Frame::Utils::uri_path,
	 'warn'						 => sub{ warn($_[0],"\n");"" },
	};

	$class->add_global_tt_params( $params );
}

1;


##############################################################################


=head1 AUTHOR

Jonas Liljegren E<lt>jonas@paranormal.seE<gt>

=head1 SEE ALSO

L<Template>

=cut

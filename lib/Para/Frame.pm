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
use Time::HiRes qw( time );
use Data::Dumper;
use Carp qw( cluck confess );
use Template;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Config;
use Para::Frame::Request;
use Para::Frame::Widget;
use Para::Frame::Utils qw( throw uri2file );


# Do not init variables here, since this will be redone each time code is updated
our $SERVER     ;
our $DEBUG      ;
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

sub startup
{
    my( $class ) = @_;

    # Start up other classes
    #
    Para::Frame::Route->on_startup;
    Para::Frame::Widget->on_startup;

    my $port = $CFG->{'port'};

    # Set up the tcp server. Must do this before chroot.
    $SERVER= IO::Socket::INET->new(
				   LocalPort => $port,
				   Proto    => 'tcp',
				   Listen  => 10,
				   Reuse  => 1,
				   )
	or (die "Cannot connect to socket $port: $@\n");

    print("Connected to port $port.\n");


    nonblock($SERVER);
    $SELECT = IO::Select->new($SERVER);

    # Setup signal handling
    $SIG{CHLD} = \&REAPER;
    
    print("Setup complete, accepting connections.\n");

#    open STDERR, ">/tmp/paraframe.log" or die $!;

    $LEVEL = 0;
    main_loop();
}

sub main_loop
{
    my( $child ) = @_;

    if( $child )
    {
	$LEVEL ++;
    }
    warn "Entering main_loop at level $LEVEL\n";


    my $timeout = 5;

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
		    warn("Problem with accept(): $!");
		    next;
		}
		($port, $iaddr) = sockaddr_in(getpeername($client));
		$peer_host = gethostbyaddr($iaddr, AF_INET) || inet_ntoa($iaddr);
		$SELECT->add($client);
		nonblock($client);

		warn "\n\nNew client connected\n" if $DEBUG > 3;
	    }
	    else
	    {
		$REQ = undef;
		get_value( $client );
	    }
	}

	### Do the jobs piled up
	#
	$timeout = 5; # We change this if there are jobs to do
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
		warn "  Found a job ($cmd) in $req->{reqnum}\n"
		    if $DEBUG > 1;
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
		warn "  All jobs done\n" if $DEBUG;
		$req->run_hook('done');
		close_callback($req->{'client'});
	    }

	    $timeout = 0.001; ### Get the jobs done quick
	}


	### Waiting for a child?
	#
	if( $child )
	{
	    # exit loop if child done
	    last unless $child->{'req'}{'childs'};

#	    warn "Waiting for a child\n";
#	    my $childs = $child->req->{'childs'};
#	    warn "  childs: $childs\n";
#	    sleep;
	}
    }
    warn "Exiting main_loop at level $LEVEL\n";
    $LEVEL --;
}


sub switch_req
{
    if( $_[0] ne $REQ )
    {
	warn "\nSwitching to req $_[0]->{reqnum}\n"; ### DEBUG

	Para::Frame->run_hook(undef, 'before_switch_req');

	if( $REQ = $_[0] )
	{
	    $U   = $REQ->s->u;
	    %ENV = %{$REQ->env}; # TODO: eliminate duplicate copy
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
	warn "  Getting value inside a fork\n";
	while( $_ = <$Para::Frame::Client::SOCK> )
	{
	    if( s/^([\w\-]{3,10})\0// )
	    {
		my $code = $1;
		warn "$$:   Code $code\n";
		chomp;
		if( $code eq 'RESP' )
		{
		    my $val = $_;
		    warn "  RESP ($val)\n";
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

    warn "Read data...\n" if $DEBUG > 3;

    unless (defined $rv && length $data)
    {
	# EOF from client.
	close_callback($client,'eof');
	warn "End of file\n";
	return undef;
    }

    $INBUFFER{$client} .= $data;
    unless( $DATALENGTH{$client} )
    {
	warn "Length of record?\n" if $DEBUG > 3;
	# Read the length of the data string
	#
	if( $INBUFFER{$client} =~ s/^(\d+)\x00// )
	{
	    warn "Setting length to $1\n" if $DEBUG > 3;
	    $DATALENGTH{$client} = $1;
	}
	else
	{
	    die "Strange INBUFFER content: $INBUFFER{$client}\n";
	}
    }

    if( $DATALENGTH{$client} )
    {
	warn "End of record?\n" if $DEBUG > 3;
	# Have we read the full record of data?
	#
	if( length $INBUFFER{$client} >= $DATALENGTH{$client} )
	{
	    warn "The whole length read\n" if $DEBUG > 3;

	    if( $INBUFFER{$client} =~ s/^(\w+)\x00// )
	    {
		my( $code ) = $1;
		if( $code eq 'REQ' )
		{
		    handle_request( $client, \$INBUFFER{$client} );
		}
		elsif( $code eq 'CANCEL' )
		{
		    warn "CANCEL client\n";
		    $DATALENGTH{$client} = 0;
		    close_callback($client);
		}
		elsif( $code eq 'RESP' )
		{
		    my $val = $INBUFFER{$client};
		    warn "RESP recieved ($val)\n" if $DEBUG > 1;
		    $INBUFFER{$client} = '';
		    $DATALENGTH{$client} = 0;
		    return $val;
		}
		elsif( $code eq 'URI2FILE' )
		{
		    # redirect request from child to client
		    #
		    my $val = $INBUFFER{$client};
		    $val =~ s/^(.+?)\x00// or die "Faulty val: $val";
		    my $caller_clientaddr = $1;

		    warn "URI2FILE($val) recieved\n";
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
		    warn "Returning answer $file\n";
#		    $client->send(join "\0", 'URI2FILE', $file );
		    $client->send(join "\0", 'RESP', $file );
		    $client->send("\n");
		}
		else
		{
		    warn "Strange CODE: $code\n";
		}
	    }
	    else
	    {
		warn "No code given: $INBUFFER{$client}\n";
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
	warn "  Closing down ($reason)\n";
    }
    else
    {
	warn "  Closing down\n";
    }

    delete $INBUFFER{$client};
    delete $REQUEST{$client};
    undef $REQ;
    $SELECT->remove($client);
    close($client);
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
	warn "  Child $child_pid exited with status $?\n";

	if( my $child = delete $CHILD{$child_pid} )
	{
	    $child->deregister( $? );
	}
	else
	{
	    warn "    No object registerd with PID $child_pid\n";
	    warn "      This may be Date::Manip...\n";
	}
    }
    $SIG{CHLD} = \&REAPER;  # still loathe sysV
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

    ### Create request
    my $req = new Para::Frame::Request( $client, $recordref, $REQNUM );

    ### Register the request
    $REQUEST{ $client } = $req;
    switch_req( $req );

    # Authenticate user identity
    $Para::Frame::CFG->{user_class}->authenticate_user;

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
}

sub add_hook
{
    my( $class, $label, $code ) = @_;

    warn "  add_hook $label from ".(caller)."\n" if $DEBUG > 2;

    # Validate hook label
    unless( $label =~ /^( on_error_detect   |
			  on_fork           |
			  done              |
			  user_login        |
			  user_logout       |
			  before_switch_req 
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
    if( $DEBUG > 2 )
    {
	if( $req )
	{
	    warn "  run_hook $label for $req->{reqnum}\n";
	}
	else
	{
	    warn "  run_hook $label\n";
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
	    warn "Avoided running $hook again\n";
	}
	else
	{
	    $Para::Frame::hooks_running{"$hook"} ++;
	    switch_req( $req ) if $req;
	    &{$hook}(@_);
	    $Para::Frame::hooks_running{"$hook"} --;
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
	warn "  Incpath: @{$REQ->{'incpath'}}\n" if $DEBUG > 3;
    }
    return $REQ->{'incpath'};
}

sub configure
{
    my( $class, $cfg_in ) = @_;

    $cfg_in or die "No configuration given\n";

    # Init global variables
    #
    $DEBUG      = 0;
    $REQNUM     = 0;
    $CFG        = {};
    $PARAMS     = {};

    $CFG = $cfg_in; # Assign to global var

    ### Set main debug level
    $DEBUG = $CFG->{'DEBUG'} || 0;

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
	 INCLUDE_PATH => [ \&incpath_generator, $Para::Frame::ROOT."/inc" ],
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
	COMPILE_DIR =>  $Para::Frame::ROOT.'/var/ttc/html',
    };

    $CFG->{'th'}{'html_pre'} ||=
    {
	%th_config,
	COMPILE_DIR =>  $Para::Frame::ROOT.'/var/ttc/html_pre',
	TAG_STYLE => 'star',
    };

    $CFG->{'th'}{'plain'} ||=
    {
	INTERPOLATE => 1,
	COMPILE_DIR => $Para::Frame::ROOT.'/var/ttc/plain',
	FILTERS =>
	{
	    'uri' => sub { CGI::escape($_[0]) },
	    'lf'  => sub { $_[0] =~ s/\r\n/\n/g; $_[0] },
#	    'autoformat' => sub { autoformat($_[0]) },
	},
    };

    foreach my $ttype (keys %{$CFG->{'th'}})
    {
	$Para::Frame::th->{$ttype} =
	    Template->new(%{$CFG->{'th'}{$ttype}});
    }

    $CFG->{'port'} ||= 7788;

    $CFG->{'user_class'} ||= 'Para::Frame::User';

    $class->set_global_tt_params;
}

sub set_global_tt_params
{
    my( $class ) = @_;

    my $params =
    {
	'dump'            => \&Dumper,
	'warn'            => sub{ warn($_[0],"\n");"" },
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


package Para::Frame::Worker;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2008-2017 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Para::Frame::Worker - For worker childs

=cut

use 5.012;
use warnings;

use FreezeThaw;
use Storable qw(freeze thaw);
use Carp qw( confess );

use Para::Frame::Reload; # Not working for active workers
use Para::Frame::Sender;

use Para::Frame::Utils qw( debug throw client_send datadump validate_utf8 );

=head1 DESCRIPTION


TODO: Should pre-fork as soon as possible in order to get a small
memory footprint

=cut


##############################################################################

=head2 method

  Para::Frame::Worker->method( $obj, $methodname, @args )

This is a worker version of

  $obj->$methodname( @args )

The arguments are freezed with L<Storable/freeze>

=cut

sub method
{
    my( $class, $obj, $method, @args ) = @_;


    my $worker = $class->get_worker();
    my $port = $worker->{'port'};

    my $code = 'OMETHOD';
    my $req = $Para::Frame::REQ;

#    my @callargs = ( $req->client.'', $obj, $method, @args );
#    debug datadump(\@callargs);
#    debug 3, "Freezing $obj -> $method ( ".datadump(\@args)." )";

#    my $val  = safeFreeze( $req->id, $obj, $method, @args );
    $Storable::Deparse = 1;
    my($val) = freeze([ $req->id, $obj, $method, @args ]);
#    debug "sending $val";

    Para::Frame::Sender::connect_to_server( $port );
    $Para::Frame::Sender::SOCK or die "No socket";
    Para::Frame::Sender::send_to_server($code, \$val);

    debug 2, sprintf "Req %d waits on worker %d", $req->id, $worker->id;


    # Yielding until we get a response
    #
    $req->{'wait'} ++;
    $req->{'worker'} = $worker;
    debug 3, "Parent yield";
    $req->yield;

    my $result = delete $req->{'workerresp'};

    if( $@ = $result->exception )
    {
	die $@;
    }

    if( my( $coderef, @args ) = $result->on_return )
    {
#	warn "coderef is '$coderef'\n";
	no strict 'refs';
	$result->message( &{$coderef}( $result, @args ) );
    }

    return $result->message;
}


##############################################################################

=head2 create_worker

=cut

sub create_worker
{
    my $sleep_count = 0;
    my $pid;
    my $fh = new IO::File;

#    $fh->autoflush(1);
#    my $af = $fh->autoflush;
#    warn "--> Autoflush is $af\n";


    # Please no signals in the middle of the forking
    $SIG{CHLD} = 'DEFAULT';

    do
    {
	eval # May throw a fatal "Can't fork"
	{
	    $pid = open($fh, "-|");
	};
	unless( defined $pid )
	{
	    debug(0,"cannot fork: $!");
	    if( $sleep_count++ > 6 )
	    {
		$SIG{CHLD} = \&Para::Frame::REAPER;
		die "Realy can't fork! bailing out";
	    }
	    sleep 1;
	}
	$@ = undef;
    } until defined $pid;

    if( $pid )
    {
	### --> parent

	# Do not block on read, since we will try reading before all
	# data are sent, so that the buffer will not get full
	#
	$fh->blocking(0);

	my $child = Para::Frame::Child->register_worker( $pid, $fh );

	# Now we can turn the signal handling back on
	$SIG{CHLD} = \&Para::Frame::REAPER;

	# See if we got any more signals
	&Para::Frame::REAPER;
	return $child;
    }
    else
    {
	### --> child

	$Para::Frame::FORK = 1;
        $Para::Frame::SELECT = undef;
 	my $result = Para::Frame::Child::Result->new;

	if( $Para::Frame::REQ )
	{
	    $Para::Frame::REQ->run_hook('on_fork', $result );
	    $Para::Frame::REQ->{'child_result'} = $result;
	}
	else
	{
	    Para::Frame->run_hook( undef, 'on_fork', $result );
	}

	return $result;
   }
}


##############################################################################

=head2 create_idle_worker

=cut

sub create_idle_worker
{
    my( $class, $count ) = @_;
    $count ||= 1;
    for( my $i=1; $i<=$count; $i++ )
    {
	debug 2, "Creating a worker";
	my $worker = $class->create_worker();
	$class->init($worker);
	push @Para::Frame::WORKER_IDLE, $worker;
    }
    return $count;
}


##############################################################################

=head2 get_worker

=cut

sub get_worker
{
    my( $class ) = @_;

    if( my $worker = pop @Para::Frame::WORKER_IDLE )
    {
	debug 2, sprintf "Reusing worker %d", $worker->id;
	return $worker;
    }

    my $worker = $class->create_worker();
    return $class->init($worker);
}


##############################################################################

=head2 init

=cut

sub init
{
    my( $class, $worker ) = @_;

    if( $worker->in_child )
    {
 	debug 3, "In child";

	my $timeout = 60;
	my $res;

	my $wsock = IO::Socket::INET->new(
				   LocalPort  => 0, # Pick an unused
				   Proto      => 'tcp',
				   Listen     => 5,
				   ReuseAddr  => 1,
				   Blocking   => 0,
				   );
	my $port = $wsock->sockport;
	my $wselect = IO::Select->new($wsock);

	debug 2, "using port '$port'";
	print "$port\n"; ### Telling what port to use;
	my $cnt =0;

      WORKLOOP:
	while( 1 )
	{
	    $worker->reset;

	    my $inbuffer = "";
	    my $datalength;
	    my $rest;
	    while( my( $wclient ) = $wselect->can_read( $timeout ) )
	    {
		debug 3, "worker can read";
		if( $wclient == $wsock ) # new connection
		{
		    debug 3, "  new connection";
		    my $awclient = $wsock->accept;
		    $wselect->add( $awclient );
		    $awclient->blocking(0);
		}
		else
		{
		    while( my $block = <$wclient> )
		    {
			$inbuffer .= $block;
			debug 3, "got message block";
#			debug "got message: $block\n";
		    }

		    unless( $datalength )
		    {
#			debug "Length of block is ".bytes::length($inbuffer);
			if( $inbuffer =~ s/^(\d+)\x00// )
			{
			    $datalength = $1;
			    debug 3, "Datalength $datalength";
			}
			elsif( not length $inbuffer )
			{
			    debug "EOF for $wclient";
			    $wselect->remove($wclient);
			    $wclient->close;
			    next;
			}
			else
			{
			    die "Strange INBUFFER content: $inbuffer\n";
			}
		    }

		    my $length_buffer = length($inbuffer||'');
		    if( $datalength and $datalength <= $length_buffer )
		    {
			$rest = substr( $inbuffer,
					$datalength,
					($length_buffer - $datalength),
					'' );

			unless( $inbuffer =~ s/^(\w+)\x00// )
			{
			    die "No code given: $inbuffer";
			}

			my( $code ) = $1;

			if( $code eq 'OMETHOD' ) # list context
			{

#			    debug validate_utf8(\$inbuffer);
			    utf8::decode($inbuffer);
#			    debug validate_utf8(\$inbuffer);

#			    my( $req_id, $obj, $method, @args ) = thaw($inbuffer);

			    local $Storable::Eval = 1;
			    my( $req_id, $obj, $method, @args ) = @{thaw($inbuffer)};
#			    debug "inbuffer $inbuffer";
			    debug 2, "Doing $method";
#			    debug "obj ".datadump($obj);
#			    debug "args ".datadump(\@args);

			    eval
			    {
				my( @res ) = $obj->$method(@args);
#				my( @res ) = {testing=>1}; ### TEST
#				debug "Sleeping ".sleep(10);
				$worker->{'message'} = \@res;
			    };
			    if( $@ )
			    {
				debug $@;
				$worker->exception( $@ );
			    }



			    debug 3, "Freezing result";
#			    my $data = safeFreeze( $req_id, $worker );
#			    my $data = FreezeThaw::safeFreeze($req_id, $worker);

			    $Storable::Deparse = 1;
			    my( $data ) = freeze([$req_id, $worker]);
			    my $port = $Para::Frame::CFG->{'port'};
			    Para::Frame::Sender::connect_to_server( $port );
			    $Para::Frame::Sender::SOCK or die "No socket";
			    debug 2, "Sending response";
			    Para::Frame::Sender::send_to_server('WORKERRESP', \$data);


			    # Another method would be to send result to on $wclient socket
#			    my $length = length($data);
#			    client_send( $wclient, \($length . "\0" . $data) );

			    debug 3, "Done";
			    $wclient->shutdown(2); # Finished
			    $wselect->remove($wclient);
			    $wclient->close;
			}
			else
			{
			    die "code $code not recognized";
			}


#			debug "Got code $code with val\n".datadump($val);

			# reset
			$inbuffer = $rest;
			$rest ='';
			$datalength = 0;


#			last WORKLOOP; ### DEBUG
		    }
		}
	    }
#	    last if $cnt++ > 50;
#	    debug "after select";
	}

	exit(0);
    }
    debug 3, "In parent";

    my $port;
    my $fh = $worker->{'fh'};
    $fh->blocking(1);
    $port= $fh->getline;
    $fh->blocking(0);
    chomp( $port );
    debug 3, "using port '$port'";
    $worker->{'port'} = $port;

    return $worker;
}


##############################################################################

1;


=head1 AUTHOR

Jonas Liljegren E<lt>jonas@paranormal.seE<gt>

=head1 SEE ALSO

L<Para::Frame::Request>

=cut

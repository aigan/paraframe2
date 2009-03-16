#!perl
# -*-cperl-*-


use 5.010;
use strict;
use warnings;

use Test::Warn;
use Test::More tests => 59;
#use Test::More qw(no_plan);
use Storable qw( freeze dclone );
use FindBin;
use Cwd 'abs_path';



BEGIN
{
    open my $oldout, ">&STDOUT"     or die "Can't dup STDOUT: $!";
    open STDOUT, ">/dev/null"       or die "Can't dup STDOUT: $!";

    use_ok('Para::Frame');

    open STDOUT, ">&", $oldout      or die "Can't dup \$oldout: $!";
}

my $approot = $FindBin::Bin . "/app";
my $pfdir = abs_path($FindBin::Bin.'/..');

my $cfg_in =
{
 'paraframe'=> $pfdir,
 'appbase'  => 'Para::MyTest',
 'approot'  => $approot,
 'port'     => 9999,
 'dir_var'  => $pfdir.'/tmp/var',
 'debug'    => 0,
};

my $client_data =
  [
   {},
   {
    DOCUMENT_ROOT        => $approot."/www/",
    GATEWAY_INTERFACE    => "CGI/1.1",
    HTTP_ACCEPT          => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    HTTP_ACCEPT_CHARSET  => "ISO-8859-1,utf-8;q=0.7,*;q=0.7",
    HTTP_ACCEPT_ENCODING => "gzip,deflate",
    HTTP_ACCEPT_LANGUAGE => "sv,en;q=0.5",
    HTTP_CONNECTION      => "keep-alive",
    HTTP_COOKIE          => "paraframe-sid=1231334731-3; AWSUSER_ID=awsuser_id1228312333525r8791; AWSSESSION_ID=awssession_id1231334738627r8335",
    HTTP_HOST            => "frame.para.se",
    HTTP_KEEP_ALIVE      => 300,
    HTTP_USER_AGENT      => "Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.9.0.4) Gecko/2008111318 Ubuntu/9.04 (jaunty) Firefox/3.0.5",
    MOD_PERL             => "mod_perl/2.0.4",
    MOD_PERL_API_VERSION => 2,
    PATH                 => "/usr/local/bin:/usr/bin:/bin",
    QUERY_STRING         => "",
    REMOTE_ADDR          => "213.88.136.203",
    REMOTE_PORT          => 59248,
    REQUEST_METHOD       => "GET",
    REQUEST_URI          => "/test/",
    SCRIPT_FILENAME      => $approot."/www/test/",
    SCRIPT_NAME          => "/test/",
    SERVER_ADDR          => "213.88.136.203",
    SERVER_ADMIN         => "webmaster\@localhost",
    SERVER_NAME          => "frame.para.se",
    SERVER_PORT          => 80,
    SERVER_PROTOCOL      => "HTTP/1.1",
    SERVER_SIGNATURE     => "<address>Apache/2.2.9 (Ubuntu) mod_perl/2.0.4 Perl/v5.10.0 Server at frame.para.se Port 80</address>\n",
    SERVER_SOFTWARE      => "Apache/2.2.9 (Ubuntu) mod_perl/2.0.4 Perl/v5.10.0",
   },
   "/test/",
   $approot."/www/test/",
   "text/html; charset=UTF-8",
   {port => 9999, site => "test" },
   0,
   {},
  ];



warnings_like {Para::Frame->configure($cfg_in)}
[ qr/^Timezone set to /,
  qr/^Stringify now set$/,
  qr/^Regestring ext tt to burner html$/,
  qr/^Regestring ext css_tt to burner plain$/,
  qr/^Regestring ext js_tt to burner plain$/,
  ],
    "Configuring";

my $cfg = $Para::Frame::CFG;
my $burner = Para::Frame::Burner->get_by_type('html');

warnings_like
{
    Para::Frame::Site->add({
			    'code'        => 'test',
			    'name'        => 'Testing',
			    'webhome'     => '/test',
			    'webhost'     => 'frame.para.se',
			   });
}[ qr/^Registring site Testing$/], "site registration";



use_ok('Para::Frame::Watchdog');
use_ok('Para::Frame::Client');



# Capture STDOUT
$|=1;
my $stdout = "";
open my $oldout, ">&STDOUT"         or die "Can't save STDOUT: $!";
close STDOUT;
open STDOUT, ">:scalar", \$stdout   or die "Can't dup STDOUT to scalar: $!";


warnings_like
{
    Para::Frame->startup;
}[
  qr/^Connected to port 9999$/,
  qr/^Setup complete, accepting connections$/,
 ], "startup";

is( $stdout, "STARTED\n", "startup output" );
clear_stdout();


%Para::Frame::Request::URI2FILE =
  (
   'frame.para.se/test/' => $approot.'/www/test/',
   'frame.para.se/test/index.tt' => $approot.'/www/test/index.tt',
   'frame.para.se/test/index.en.tt' => $approot.'/www/test/index.en.tt',
   'frame.para.se/test/def/index.en.tt' => $approot.'/www/test/def/index.en.tt',
   'frame.para.se/test/def/index.tt' => $approot.'/www/test/def/index.tt',
   'frame.para.se/test/page_not_found.tt' => $approot.'/www/test/page_not_found.tt',
   'frame.para.se/test/page_not_found.en.tt' => $approot.'/www/test/page_not_found.en.tt',
   'frame.para.se/test/def/page_not_found.en.tt' => $approot.'/www/test/def/page_not_found.en.tt',
   'frame.para.se/test/def/page_not_found.tt' => $approot.'/www/test/def/page_not_found.tt',
  );


remove_files_with_bg_req(); # REQ 1

test_ping();
test_ping2();
test_fill_buffer();

test_handle_req();          # REQ 2
test_cancel_req();          # REQ cancelled
test_cancel2_req();         # REQ 3


#############################################

sub remove_files_with_bg_req
{
    my @got_warning = ();
  TEST:
    {
	local $SIG{__WARN__} = sub
	{
	    push @got_warning, shift();
	};

	my $req = Para::Frame::Request->new_bgrequest();
	clear_stdout();

	Para::Frame::Dir->new({ filename => $pfdir.'/tmp', file_may_not_exist=>1})->remove;
	# Different output depending on existence of tmp dir
	like( $stdout, qr/MAINLOOP 1\n|/, "Gone through mainloop" );
	clear_stdout();

	$req->done;
    }

    my @expected =
      (
       qr/^\n\n1 Handling new request \(in background\)\n$/,
       qr/^\s*Removing dir /,
       qr/^\s*Removing file /,
       qr/^\s*File .* created from the outside/m,
       qr/^1 Done in   0\.\d\d secs$/,
      );

    my @failed;
  TESTRES:
    foreach my $warn ( @got_warning )
    {
#	warn "# checking $warn\n";
	foreach my $re ( @expected )
	{
#	    warn "  with pattern $re\n";
	    if( $warn =~ $re )
	    {
		next TESTRES;
	    }
	}
#	warn "  failed\n";
	push @failed, $warn;
    }

    if( scalar @failed )
    {
	my $err = join ', ', @failed;
	$err =~ s/\n/ /g;
	ok(0, "Removing tmp: $err");
    }
    else
    {
	ok(1, "Removing tmp");
    }

}

#############################################

sub test_ping
{
    Para::Frame::Watchdog::send_to_server('PING');

    # New connection
    my( $client ) = $Para::Frame::SELECT->can_read( 1 );
    isa_ok($client, 'IO::Socket::INET', 'client');
    is( $client, $Para::Frame::SERVER, 'new connection' );
    Para::Frame::add_client( $client );

    # New data
    ( $client ) = $Para::Frame::SELECT->can_read( 1 );
    isa_ok($client, 'IO::Socket::INET', 'client');
    isnt( $client, $Para::Frame::SERVER, 'new data' );

    Para::Frame::switch_req(undef); # TODO: remove me
    Para::Frame::get_value( $client );

    # Watchdog Read response
    my $select = IO::Select->new($Para::Frame::Watchdog::SOCK);
    isa_ok($select, 'IO::Select', 'select');
    ok( $select->can_read( 1 ), 'can_read' );
    my $resp = $Para::Frame::Watchdog::SOCK->getline;
    my $length;
    ok( ($resp =~ s/^(\d+)\x00//), 'got length' );
    ok( ($1 == 5), 'right length' );
    ok( ($resp eq "PONG\0"), "right answer" );
}


#############################################

sub test_ping2
{
    my $sock = wd_open_socket();
    my $dataref = wd_format_data('PING');
    wd_send_data( $sock, $dataref );
#    wd_send_data( $sock, 'PING' );

    # New connection
    my( $client ) = $Para::Frame::SELECT->can_read( 1 );
    is( $client, $Para::Frame::SERVER, 'new connection' );
    Para::Frame::add_client( $client );

    # New data
    ( $client ) = $Para::Frame::SELECT->can_read( 1 );
    isnt( $client, $Para::Frame::SERVER, 'new data' );

    Para::Frame::switch_req(undef); # TODO: remove me

  HANDLE:
    {
	Para::Frame::fill_buffer($client) or last;
	Para::Frame::handle_code($client) and redo; # Read more if availible
    }

    # Watchdog Read response
    my $select = IO::Select->new($sock);
    ok( $select->can_read( 1 ), 'can_read' );
    my $resp = $sock->getline;
    my $length;
    ok( ($resp =~ s/^(\d+)\x00//), 'got length' );
    ok( ($1 == 5), 'right length' );
    ok( ($resp eq "PONG\0"), "right answer" );
}


#############################################

sub test_handle_req
{
    my $value = freeze $client_data;

    Para::Frame::Client::connect_to_server( $Para::Frame::CFG->{'port'} );
    Para::Frame::Client::send_to_server('REQ', \$value );

    # New connection
    my( $client ) = $Para::Frame::SELECT->can_read( 1 );
    is( $client, $Para::Frame::SERVER, 'new connection' );
    Para::Frame::add_client( $client );

    # New data
    ( $client ) = $Para::Frame::SELECT->can_read( 1 );
    isnt( $client, $Para::Frame::SERVER, 'new data' );

    Para::Frame::switch_req(undef); # TODO: remove me


    my @got_warning = ();
  TEST:
    {
	local $SIG{__WARN__} = sub
	{
	    push @got_warning, shift();
	};
	Para::Frame::get_value( $client );
    }

    my @expected =
      (
       qr/^\n\n2 Handling new request\n$/,
       qr/^\# http:\/\/frame.para.se\/test\/\n$/m,
       qr/^\# 20\d\d-\d\d-\d\d \d\d\.\d\d\.\d\d - 213\.88\.136\.203\n\# Sid 1231334731-3 - 0 - Uid 0 - debug 0\n$/m,
       qr/^  This is the first request in this session$/,
       qr/^  Rendering page$/,
       qr/^  Decoding UTF-8 file .*?\/html\/index\.tt \(<unknown>\) 20\d\d-\d\d-\d\dT\d\d:\d\d:\d\d$/,
       qr/^  Compiling .*?\/html\/index\.tt$/,
       qr/^Sending response\.\.\.$/,
       qr/^2 Done in   \d\.\d\d secs$/,
      );

    for( my $i=0; $i<=$#got_warning; $i++ )
    {
	like( $got_warning[$i], $expected[$i], "Processing request - warning $i" );
    }

    is( $stdout, "", "no stdout" );
}


#############################################

sub test_cancel_req
{
    my $value = freeze $client_data;

    Para::Frame::Client::connect_to_server( $Para::Frame::CFG->{'port'} );
    Para::Frame::Client::send_to_server('REQ', \$value );

    Para::Frame::Client::send_to_server('CANCEL', \1 );

    # New connection
    my( $client ) = $Para::Frame::SELECT->can_read( 1 );
    is( $client, $Para::Frame::SERVER, 'new connection' );
    Para::Frame::add_client( $client );

    # New data
    ( $client ) = $Para::Frame::SELECT->can_read( 1 );
    isnt( $client, $Para::Frame::SERVER, 'new data' );

    Para::Frame::switch_req(undef); # TODO: remove me


    warning_like
    {
	Para::Frame::get_value( $client );
    } qr/^SKIPS CANCELLED REQ$/, "Skips cancelled req";

    is( $stdout, "", "no stdout" );
}


#############################################

sub test_cancel2_req
{
    my $cd2 = dclone( $client_data );
    # make modifications

    $cd2->[0]{run}  = ["take_five"];
    $cd2->[0]{count}  = [1];
    $cd2->[1]{QUERY_STRING} = "run=take_five&count=1";
    $cd2->[1]{REQUEST_URI} = "/test/?run=take_five&count=1";

    my $value = freeze $cd2;

    Para::Frame::Client::connect_to_server( $Para::Frame::CFG->{'port'} );
    Para::Frame::Client::send_to_server('REQ', \$value );


    # New connection
    my( $client ) = $Para::Frame::SELECT->can_read( 1 );
    is( $client, $Para::Frame::SERVER, 'new connection' );
    Para::Frame::add_client( $client );

    # New data
    ( $client ) = $Para::Frame::SELECT->can_read( 1 );
    isnt( $client, $Para::Frame::SERVER, 'new data' );

    Para::Frame::switch_req(undef); # TODO: remove me

    Para::Frame::fill_buffer($client);
    Para::Frame::Client::send_to_server('CANCEL', \1 );

    my @got_warning = ();
  TEST:
    {
	local $SIG{__WARN__} = sub
	{
	    push @got_warning, shift();
	};
	eval
	{
	    Para::Frame::handle_code($client);
	};
    }

    is( "$@", 'cancel error - Request cancelled. Stopping jobs', "Cancel exception" );
    undef $@;

    is( $stdout, "MAINLOOP 1\n", "got through mainloop" );

    my @expected =
      (
       qr/^\n\n3 Handling new request\n$/,
       qr/^\# http:\/\/frame.para.se\/test\/\n$/m,
       qr/^\# 20\d\d-\d\d-\d\d \d\d\.\d\d\.\d\d - 213\.88\.136\.203\n\# Sid 1231334731-3 - 1 - Uid 0 - debug 0\n$/m,
       qr/^      CANCEL req 3$/,
       qr/^  cancelled by request$/,
       qr/^3 Done in   1\.\d\d secs$/,
       qr/^  ACTION FAILED!$/,
      );

    for( my $i=0; $i<=$#got_warning; $i++ )
    {
	like( $got_warning[$i], $expected[$i], "Processing request - warning $i" );
    }
}


#############################################

sub test_fill_buffer
{
    my $sock = wd_open_socket();

#    my $testdata = join '-', (1..10000); # 48893

    my $testdata = join '-', (1..10);
    my $dataref = wd_format_data('TESTa', \$testdata);

    my $testdata2 = join '-', (1..8);
    my $dataref2 = wd_format_data('TESTb', \$testdata2);

    my $testdata3 = join '-', (1..1000); # 48893
    my $dataref3 = wd_format_data('TESTc', \$testdata3);

    my $bigdata = $$dataref . $$dataref2 . $$dataref3;
#    my $bigdata = $$dataref . $$dataref2;

    my $chunk1 = substr $bigdata, 0,35;
    my $chunk2 = substr $bigdata, 35, 100;
    my $chunk3 = substr $bigdata, 135;

#    warn "1: $chunk1\n";
#    warn "2: $chunk2\n";
#    warn "3: $chunk3\n";

    wd_send_data( $sock, \$chunk1 );


    # New connection
    my( $client ) = $Para::Frame::SELECT->can_read( 1 );
    is( $client, $Para::Frame::SERVER, 'new connection' );
    Para::Frame::add_client( $client );

    # New data
    ( $client ) = $Para::Frame::SELECT->can_read( 1 );
    isnt( $client, $Para::Frame::SERVER, 'new data' );

    Para::Frame::switch_req(undef); # TODO: remove me

    Para::Frame::fill_buffer($client);

#    warn "inbuffer: ".$Para::Frame::INBUFFER{$client};
#    warn "datalength: ".$Para::Frame::DATALENGTH{$client};

    # Chunk 1
    my( $code, $data ) = pf_extract_code( $client );
    ok( ($code eq 'TESTa'), "TESTa" );
    ok( ($data eq $testdata), "TESTa data" );


    # Chunk 2
    wd_send_data( $sock, \$chunk2 );
    Para::Frame::fill_buffer($client);
#    warn "inbuffer: ".$Para::Frame::INBUFFER{$client};
#    warn "datalength: ".$Para::Frame::DATALENGTH{$client};
    ( $code, $data ) = pf_extract_code( $client );
    ok( ($code eq 'TESTb'), "TESTb" );
    ok( ($data eq $testdata2), "TESTb data" );


    # Chunk 3
    wd_send_data( $sock, \$chunk3 );
    Para::Frame::fill_buffer($client);
#    warn "inbuffer: ".$Para::Frame::INBUFFER{$client};
#    warn "datalength: ".$Para::Frame::DATALENGTH{$client};
    ( $code, $data ) = pf_extract_code( $client );
    ok( ($code eq 'TESTc'), "TESTc" );
    ok( ($data eq $testdata3), "TESTc data" );

    Para::Frame::close_callback( $client );

}


#############################################

sub wd_open_socket
{
    my $DEBUG = 1;

    my @cfg =
	(
	 PeerAddr => 'localhost',
	 PeerPort => $Para::Frame::CFG->{'port'},
	 Proto    => 'tcp',
	 Timeout  => 5,
	 );

    my $sock = IO::Socket::INET->new(@cfg);

    my $try = 1;
    while( not $sock )
    {
	$try ++;
	warn "$$:   Trying again to connect to server ($try)\n" if $DEBUG;

	$sock = IO::Socket::INET->new(@cfg);

	last if $sock;

	if( $try >= 5 )
	{
	    warn "$$: Tried connecting to server $try times - Giving up!\n";
	    last;
	}

	sleep 1;
    }

    if( $sock )
    {
	binmode( $sock, ':raw' );
	warn "$$: Established connection to server\n" if $DEBUG > 3;
    }
    else
    {
	warn "Failed to connect to server";
	return undef;
    }

    return $sock;
}


#############################################

sub wd_format_data
{
    my( $code, $valref ) = @_;
    my $DEBUG = 1;

    $valref ||= \ "1";
    my $length_code = length($$valref) + length($code) + 1;
    my $data = "$length_code\x00$code\x00" . $$valref;

    return \$data;
}


#############################################

sub wd_send_data
{
    my( $sock, $dataref ) = @_;
    my $DEBUG = 1;

    my $data = $$dataref;

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
	$sent = $sock->send( substr $data, $i, $chunk );
	if( $sent )
	{
	    $errcnt = 0;
	}
	else
	{
	    Para::Frame::Watchdog::check_server_report();
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


#############################################

sub pf_extract_code
{
    my( $client ) = @_;

    # Parse record
    #
    my $length_target = $Para::Frame::DATALENGTH{$client};
    my $length_buffer = length( $Para::Frame::INBUFFER{$client}||='' );
    my $rest = '';

    if( $length_buffer > $length_target )
    {
	$rest = substr( $Para::Frame::INBUFFER{$client},
			$length_target,
			($length_buffer - $length_target),
			'' );
    }

#    warn "Buffer: $Para::Frame::INBUFFER{$client}\n";

    unless( $Para::Frame::INBUFFER{$client} =~ s/^(\w+)\x00// )
    {
	warn "No code given: $Para::Frame::INBUFFER{$client}\n";
	close_callback($client,'faulty input');
	return 0;
    }


    my( $code ) = $1;
#    warn "GOT code $code: $Para::Frame::INBUFFER{$client}\n";

    my $data = $Para::Frame::INBUFFER{$client};
    $Para::Frame::INBUFFER{$client} = $rest;
    $Para::Frame::DATALENGTH{$client} = 0;

    return( $code, $data );
}

sub clear_stdout
{
    close STDOUT;
    $stdout="";
    open STDOUT, ">:scalar", \$stdout   or die "Can't dup STDOUT to scalar: $!";
}


#############################################
#############################################
#############################################
#############################################

no warnings 'redefine';

package Para::Frame::Site;

sub uri2file
{
    my( $site, $url, $file, $may_not_exist ) = @_;

    my $req = $Para::Frame::REQ;
    $url =~ s/\?.*//; # Remove query part if given
    my $key = $req->host . $url;

    if( $file )
    {
	confess "DEPRECATED";
	warn "Storing URI2FILE in key $key: $file\n";
	return $Para::Frame::Request::URI2FILE{ $key } = $file;
    }

    if( $file = $Para::Frame::Request::URI2FILE{ $key } )
    {
#	warn "Return  URI2FILE for $key: $file\n";
	return $file;
    }

    confess "url missing" unless defined $url;

    warn "uri2file $key\n";

    if( $url =~ m/^\/var\/ttc\// )
    {
	debug "The ttc dir shoule not reside inside a site docroot";
    }

    use Data::Dump;
    warn Data::Dump::dump( \%Para::Frame::Request::URI2FILE );

    die "uri2file not pre-defined\n";
}


#############################################

package Para::Frame::Request::Response;

sub send_output
{
    my( $resp ) = @_;
    warn "Sending response...\n";
}


1;

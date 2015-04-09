#!perl

use 5.010;
use strict;
use warnings;

use Test::Warn;
use Test::More tests => 26;
#use Test::More qw(no_plan);
use Storable qw( freeze dclone );
use FindBin;
use Cwd 'abs_path';

our $stdout;
our @got_warning;
our $DEBUG;


BEGIN
{
    $DEBUG = 0;

    unless( $DEBUG )
    {
        $SIG{__WARN__} = sub{ push @got_warning, shift() };
    }

    open(SAVEOUT, ">&STDOUT");
    #    open(SAVEERR, ">&STDERR");

    close( STDOUT );
    open STDOUT, ">/dev/null"       or die "Can't dup STDOUT: $!";

    use_ok('Para::Frame');

    open STDOUT, ">&", SAVEOUT      or die "Can't restore STDOUT: $!";
}

my $approot = $FindBin::Bin . "/app";
my $pfdir = abs_path($FindBin::Bin.'/../share');

my $cfg_in =
{
    'paraframe'=> $pfdir,
    'appbase'  => 'Para::MyTest',
    'approot'  => $approot,
    'port'     => 9999,
    'dir_var'  => $pfdir.'/tmp/var',
    'debug'    => $DEBUG,
    'ajax_renderer_class' => 'Para::Frame::Renderer::Test_AJAX',
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
[ qr/^Registring ext tt to burner html$/,
  qr/^Registring ext html_tt to burner html$/,
  qr/^Registring ext xtt to burner html$/,
  qr/^Registring ext css_tt to burner plain$/,
  qr/^Registring ext js_tt to burner plain$/,
  qr/^Registring ext css_dtt to burner plain$/,
  qr/^Registring ext js_dtt to burner plain$/,
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
}[ qr/^Registring site frame.para.se\/test$/], "site registration";



use_ok('Para::Frame::Watchdog');
use_ok('Para::Frame::Sender');



# Capture STDOUT
$|=1;
#my $stdout = "";
#open my $oldout, ">&STDOUT"         or die "Can't save STDOUT: $!";
#close STDOUT;
#open STDOUT, ">:scalar", \$stdout   or die "Can't dup STDOUT to scalar: $!";

clear_stdout();


warnings_like
{
    Para::Frame->startup;
}[
    #  qr/^Looking up site default$/,
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


#remove_files_with_bg_req(); # REQ 1

eval
{
    test_fill_buffer();
} or diag $@;
#diag( "Warnings:\n".join("",@got_warning ) );

#test_cancel_req();          # REQ cancelled


#############################################

sub test_fill_buffer
{

#    my $testdata1 = generate_http(1);
#    my $testdata2 = generate_http(12);
#    my $testdata3 = generate_http(123);
#    my $testdata4 = generate_http(1234);
#
#    my $bigdata = $testdata3 . $testdata4;
#
#    my $chunk1 = $testdata1;              # exact
#    my $chunk2 = $testdata2 . "\r\n\r\n" . $testdata3; # double
#    my $chunk3 = substr $bigdata, 0, 256; # less
#    my $chunk4 = substr $bigdata, 256;    # rest

     
    my( $sock, $client, $data, $expect, $chunk1, $chunk2, $res );

    # New connection
#    $sock = wd_open_socket();
#    ( $client ) = $Para::Frame::SELECT->can_read( 1 );
#    is( $client, $Para::Frame::SERVER, 'new connection' );


    # Buffertest - GET
    #
    @got_warning = ();
    $sock = wd_open_socket();
    $chunk1 = generate_http(1, 'get');
    wd_send_data( $sock, \$chunk1 );
    $client = new_connection();
    Para::Frame::get_value($client);
    $data = get_response( $sock );
    $sock->close;
    check_data($data,"1", "Buffertest - GET");
    


    # Buffertest - POST
    #
    @got_warning = ();
    $sock = wd_open_socket();
    $chunk1 = generate_http(12, 'post');
    wd_send_data( $sock, \$chunk1 );
    $client = new_connection();
    Para::Frame::get_value($client);
    $data = get_response( $sock );
    $sock->close;
    check_data($data,"12", "Buffertest - POST");


    

    # Buffertest - POST divided
    #
#    diag "************************************ Buffertest";
    $TEST::DIE = 0;
    @got_warning = ();
    $sock = wd_open_socket();
        ($chunk1, $chunk2) = generate_http(123, 'post') =~ m/(.*\r\n\r\n)(.*)/s;
#    diag "Chunk 1:\n$chunk1\n.";
#    diag "Chunk 2:\n$chunk2\n.";
    wd_send_data( $sock, \$chunk1 );
#    wd_send_data( $sock, \$chunk2 );
    $client = new_connection();
#    Para::Frame::get_value($client);
    Para::Frame::fill_buffer($client);
#    diag "INBUFFER 1 ".$Para::Frame::INBUFFER{$client};
    wd_send_data( $sock, \$chunk2 );
#    diag "***** Reading chunk2";
    Para::Frame::get_value($client);
    $data = get_response( $sock );
#    diag "Response: ".$data;
#    like( $data, qr/\\"123\\"/, "Buffertest - POST divided");
    check_data($data,"123", "Buffertest - POST divided");


    

    # Buffertest - GET pipelining spaced
    #
    @got_warning = ();
    $sock = wd_open_socket();
    $chunk1 = generate_http(1234,'get');
    $chunk2 = generate_http(12345,'get');
    wd_send_data( $sock, \$chunk1 );
    $client = new_connection();
    Para::Frame::fill_buffer($client);
    wd_send_data( $sock, \$chunk2 );
    Para::Frame::get_value($client);
    $data = get_response( $sock );
    check_data($data,"1234", "Buffertest - GET pipelining spaced");



    # Buffertest - POST pipelining spaced
    #
    @got_warning = ();
    $sock = wd_open_socket();
    $chunk1 = generate_http(1234,'post');
    $chunk2 = generate_http(12345,'post');
    wd_send_data( $sock, \$chunk1 );
    $client = new_connection();
    Para::Frame::fill_buffer($client);
    wd_send_data( $sock, \$chunk2 );
    Para::Frame::get_value($client);
    $data = get_response( $sock );
    check_data($data,"1234", "Buffertest - POST pipelining spaced");


    
    # Buffertest - GET pipelining nonspaced
    #
    @got_warning = ();
    $sock = wd_open_socket();
    $chunk1 = generate_http(1234,'get');
    $chunk2 = generate_http(12345,'get');
    wd_send_data( $sock, \$chunk1 );
    wd_send_data( $sock, \$chunk2 );
    $client = new_connection();
    Para::Frame::get_value($client);
    $data = get_response( $sock );
    check_data($data,"1234", "Buffertest - GET pipelining nonspaced");


    
    # Buffertest - POST pipelining nonspaced
    #
    @got_warning = ();
    $sock = wd_open_socket();
    $chunk1 = generate_http(1234,'post');
    $chunk2 = generate_http(12345,'post');
    wd_send_data( $sock, \$chunk1 );
    wd_send_data( $sock, \$chunk2 );
    $client = new_connection();
    Para::Frame::get_value($client);
    $data = get_response( $sock );
    check_data($data,"1234", "Buffertest - POST pipelining nonspaced");



    # Buffertest - GET+POST pipelining nonspaced
    #
    @got_warning = ();
    $sock = wd_open_socket();
    $chunk1 = generate_http(1234,'get');
    $chunk2 = generate_http(12345,'post');
    wd_send_data( $sock, \$chunk1 );
    wd_send_data( $sock, \$chunk2 );
    $client = new_connection();
    Para::Frame::get_value($client);
    $data = get_response( $sock );
    check_data($data,"1234", "Buffertest - GET+POST pipelining nonspaced");


    # Buffertest - POST+GET pipelining nonspaced
    #
    @got_warning = ();
    $sock = wd_open_socket();
    $chunk1 = generate_http(1234,'post');
    $chunk2 = generate_http(12345,'get');
    wd_send_data( $sock, \$chunk1 );
    wd_send_data( $sock, \$chunk2 );
    $client = new_connection();
    Para::Frame::get_value($client);
    $data = get_response( $sock );
    check_data($data,"1234", "Buffertest - POST+GET pipelining nonspaced");




    # Buffertest - GET keepalive
    #
    @got_warning = ();
    $sock = wd_open_socket();
    $chunk1 = generate_http(1234,'get');
    $chunk2 = generate_http(12345,'get');
    wd_send_data( $sock, \$chunk1 );
    $client = new_connection();
    Para::Frame::get_value($client);
    $data = get_response( $sock );
    wd_send_data( $sock, \$chunk2 );
#    diag "*********************";
    $res = Para::Frame::fill_buffer($client);
    is( $res, '0', "Buffertest - GET keepalive (connection closed)");
#    diag "Second res: $res";
#    check_data($data,"1234", "Buffertest - GET pipelining spaced");






    
    
    diag("Incomplete. More tests to come");


















   
#
#    # Chunk 1
#    my( $code, $data ) = pf_extract_code( $client );
#    ok( ($code eq 'TESTa'), "TESTa" );
#    ok( ($data eq $testdata1), "TESTa data" );
#
#
#    # Chunk 2
#    wd_send_data( $sock, \$chunk2 );
#    Para::Frame::fill_buffer($client);
#    #    warn "inbuffer: ".$Para::Frame::INBUFFER{$client};
#    #    warn "datalength: ".$Para::Frame::DATALENGTH{$client};
#    ( $code, $data ) = pf_extract_code( $client );
#    ok( ($code eq 'TESTb'), "TESTb" );
#    ok( ($data eq $testdata2), "TESTb data" );
#
#
#    # Chunk 3
#    wd_send_data( $sock, \$chunk3 );
#    Para::Frame::fill_buffer($client);
#    #    warn "inbuffer: ".$Para::Frame::INBUFFER{$client};
#    #    warn "datalength: ".$Para::Frame::DATALENGTH{$client};
#    ( $code, $data ) = pf_extract_code( $client );
#    ok( ($code eq 'TESTc'), "TESTc" );
#    ok( ($data eq $testdata3), "TESTc data" );
#
#    Para::Frame::close_callback( $client );

}


#############################################

sub wd_open_socket
{
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
        diag "$$:   Trying again to connect to server ($try)\n" if $DEBUG;

        $sock = IO::Socket::INET->new(@cfg);

        last if $sock;

        if( $try >= 5 )
        {
            diag "$$: Tried connecting to server $try times - Giving up!\n";
            last;
        }

        sleep 1;
    }

    if( $sock )
    {
        binmode( $sock, ':raw' );
        diag "$$: Established connection to server\n" if $DEBUG > 3;
    }
    else
    {
        diag "Failed to connect to server";
        return undef;
    }

    return $sock;
}


#############################################

sub wd_format_data
{
    my( $code, $valref ) = @_;

    $valref ||= \ "1";
    my $length_code = length($$valref) + length($code) + 1;
    my $data = "$length_code\x00$code\x00" . $$valref;

    return \$data;
}


#############################################

sub wd_send_data
{
    my( $sock, $dataref ) = @_;

    my $data = $$dataref;

    if( $DEBUG > 3 )
    {
        diag "$$: Sending string $data\n";
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
                diag "$$: Got over 10 failures to send chunk $i\n";
                diag "$$: LOST CONNECTION\n";
                return 0;
            }

            diag "$$:  Resending chunk $i of messge: $data\n";
            Time::HiRes::sleep(0.05);
            redo;
        }
    }

    return 1;
}


#############################################

use constant BUFSIZ => 8192;    # Posix buffersize
sub get_response
{
    my( $sock ) = @_;

    my $data = "";
    my( $buffer, $buffer_empty_time );
    
    while()
    {
        my $rv = $sock->recv($buffer,BUFSIZ, 0);
        unless( defined $rv and length $buffer)
        {
            ### Assume all data was sent before this read.
            ### Not waiting here.
            last if length($data);

            
            if ( defined $rv )
            {
                diag("$$: Buffer empty");
                if ( $buffer_empty_time )
                {
                    if ( ($buffer_empty_time+5) < time )
                    {
                        diag("$$: For 5 secs");
                        diag("$$: Socket $sock");
                        diag("$$: atmark ".$sock->atmark);
                        diag("$$: connected ".$sock->connected);
                        
                    }
                    else
                    {
                        sleep 1;
                        next;
                    }
                }
                else
                {
                    $buffer_empty_time = time;
                    next;
                }
            }

            # EOF from server
            diag("$$: Nothing in socket $sock");
            diag("$$: rv: $rv");
            diag("$$: buffer: $buffer");
            diag("$$: EOF!");

            last;
        }

#        diag "Adding ".length($buffer)." chars to result";
        
        $data .= $buffer;
        $buffer_empty_time = undef;
    }

    return( $data );
}

#############################################

sub generate_http
{
    my( $id, $type ) = @_;

    my $http_header = "POST /ajax/1/app/testing HTTP/1.1
Host: frame.para.se:9999
Connection: keep-alive
Content-Length: 0
Origin: http://user.para.se
User-Agent: Mozilla/5.0 (X11; Linux i686) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/40.0.2214.115 Safari/537.36
Content-Type: application/x-www-form-urlencoded; charset=UTF-8
Accept-Encoding: gzip, deflate
Accept-Language: sv-SE,sv;q=0.8,en-US;q=0.6,en;q=0.4

";

    my $http_body = "cred%5Busername%5D=tester&cred%5Bpassword%5D=mycryptedpassword&data=%7B%22id%22%3A%22myid%22%7D";

    $id //= 1;
    $http_body =~ s/myid/$id/;
    
    if( $type eq 'get' )
    {
        $http_header =~ s/^Content-Length: 0\n//;
        $http_header =~ s/^POST (.*) HTTP/GET $1?$http_body HTTP/;
    }
    else
    {
        # Body only uses 8 bit characters
        my $length = length($http_body);
        $http_header =~ s/Content-Length: 0/Content-Length: $length/;
        $http_header .= $http_body;
    }

    $http_header =~ s/\n/\r\n/g;
    
    return $http_header;
}


#############################################

sub new_connection
{
    my( $client ) = $Para::Frame::SELECT->can_read( 1 );

    if( $client == $Para::Frame::SERVER )
    {
        # diag "New connection $client";
        Para::Frame::add_client( $client );
        return new_connection();
    }

    unless( $client )
    {
        diag "No connection found";
    }
    
    return $client;
}


#############################################

sub check_data
{
    my( $data, $test, $message ) = @_;
    like( $data, qr/\Q"data":["{\"id\":\"$test\"}"]/, $message." data");
    like( $data, qr/"user":"tester"/, $message." user");
}


#############################################

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

    

    die "uri2file not pre-defined: ".join("", @got_warning);
}


#############################################

package Para::Frame::Request::Response;

sub send_output
{
    my( $resp ) = @_;
    warn "Sending response...\n";
}


#############################################

package Para::Frame::File; # Imported and used from here
#package Para::Frame::Utils;

sub chmod_file
{
    return;
}


#############################################

package Para::Frame::User;

sub get
{
    my( $class, $username ) = @_;

    my $u = bless {}, $class;

    $u->{'uid'} = 0;
    $u->{'level'} = 0;

    if( $username eq "tester" )
    {
        $u->{'name'} = 'Tester';
        $u->{'username'} = 'tester';
        $u->{'uid'} = 1;
        $u->{'level'} = 5;
    }
    else
    {
        $u->{'name'} = 'Guest';
        $u->{'username'} = 'guest';
    }

    return $u;
}

sub verify_password
{
    my( $u, $password_encrypted ) = @_;

    return 1 if $u->{'level'} == 0;
    
    my $pwtable =
    {
        'tester' => 'mycryptedpassword',
    };

    my $username = $u->{'username'};

    if( my $pw = $pwtable->{$username} )
    {
        return 1 if $pw eq $password_encrypted;
        debug "Password mismatch";
    }

    debug "Got $username with ".$password_encrypted;

    return 0;
}



1;

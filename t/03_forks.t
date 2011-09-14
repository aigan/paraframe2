#!perl

use 5.010;
use strict;
use warnings;

use Test::Warn;
use Test::More tests => 12;
#use Test::More qw(no_plan);
use Storable qw( freeze dclone );
use FindBin;
use Cwd 'abs_path';

our $stdout;
our @got_warning;


BEGIN
{
    $SIG{__WARN__} = sub{ push @got_warning, shift() };

    open(SAVEOUT, ">&STDOUT");
#    open(SAVEERR, ">&STDERR");

    close( STDOUT );
#    open my $oldout, ">&STDOUT"     or die "Can't dup STDOUT: $!";
    open STDOUT, ">/dev/null"       or die "Can't dup STDOUT: $!";

    use_ok('Para::Frame');
    use_ok('Para::Frame::Utils', 'datadump');
    

    open STDOUT, ">&", SAVEOUT      or die "Can't restore STDOUT: $!";
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
#  qr/^ttcdir set to/,
  qr/^Registring ext tt to burner html$/,
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


open STDOUT, ">/dev/null"       or die "Can't dup STDOUT: $!";
open STDERR, ">/dev/null"       or die "Can't dup STDOUT: $!";
$|=1;
Para::Frame->startup;

############ Background REQ
#
Para::Frame::Request->new_bgrequest();
ok( $Para::Frame::REQ->client eq 'background-1', "BG Request" );


open STDOUT, ">&", SAVEOUT      or die "Can't restore STDOUT: $!";
#open STDERR, ">&", SAVEERR      or die "Can't restore STDOUT: $!";


####### FORKING STUFF
#$Para::Frame::DEBUG = 3;
Para::Frame::Worker->create_idle_worker(1);

open STDOUT, ">/dev/null"       or die "Can't dup STDOUT: $!";


my $worker_0 = $Para::Frame::WORKER_IDLE[0];
ok( $worker_0->in_parent, "worker init" );
ok( int(@Para::Frame::WORKER_IDLE) == 1, "Worker Idle" );


my $testobj = Test_class->new();
my $res = Para::Frame::Worker->method($testobj,'get_my_data', 'forky');

ok( $res eq "very forky data", "Worker method" );
ok( int(@Para::Frame::WORKER_IDLE) == 1, "Worker back" );

# Kill the worker and see what happens
my $pid = $worker_0->pid;
kill 9, $pid;
sleep 1; # Must kill in at most 1 second
ok( int(@Para::Frame::WORKER_IDLE) == 0, "Worker gone" );


#die "\nNEAR END";

#########################################

package Test_class;

sub new
{
    my( $class ) = @_;
    return bless {}, $class;
}

sub get_my_data
{
    return "very $_[1] data";
}

1;

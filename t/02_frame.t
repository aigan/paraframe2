#!perl
#  $Id$  -*-cperl-*-

use strict;
use warnings;
use Test::Warn;
use Test::More tests => 15;
#use Test::More qw(no_plan);


BEGIN
{
    open my $oldout, ">&STDOUT"     or die "Can't dup STDOUT: $!";
    open STDOUT, ">/dev/null"       or die "Can't dup STDOUT: $!";

    use_ok('Para::Frame');

    open STDOUT, ">&", $oldout      or die "Can't dup \$oldout: $!";
}

my $cfg_in =
{
    approot => '/tmp/approot',
    appbase => 'Para::MyTest',
    port => 9999,
};
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
			   });
}[ qr/^Registring site Testing$/], "site registration";


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
$stdout = "";


#############################################
### Check connection

use_ok('Para::Frame::Watchdog');
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

#############################################
1;

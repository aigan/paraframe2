#!perl
use strict;
use warnings;
use Data::Dumper;
use Test::Warn;
use Test::More tests => 22;


BEGIN { use_ok('Para::Frame'); }

warning_like {Para::Frame::Site->add({})} qr/^Registring site \S+$/, "Adding site";

Para::Frame->configure({
    approot => '/tmp/approot',
});

my $cfg = $Para::Frame::CFG;

is( $cfg->{'approot'}, '/tmp/approot', 'approot');
is_deeply( $cfg->{'appfmly'}, [], 'appfmly');
is( $cfg->{'dir_log'}, '/var/log', 'dir_log');
is( $cfg->{'logfile'}, '/var/log/paraframe_7788.log', 'logfile');
isa_ok( $cfg->{'th'}, 'HASH', 'th' );
my $th = $cfg->{'th'};
isa_ok( $th->{'plain'}, 'Para::Frame::Burner', 'th plain' );
isa_ok( $th->{'html'}, 'Para::Frame::Burner', 'th html' );
isa_ok( $th->{'html_pre'}, 'Para::Frame::Burner', 'th html_pre' );
is_deeply( $cfg->{'appback'}, [], 'appback');
is( $cfg->{'dir_var'}, '/var', 'dir_var');
is( $cfg->{'port'}, 7788, 'port');
is( $cfg->{'paraframe'}, '/usr/local/paraframe', 'paraframe');
isa_ok($cfg->{'bg_user_code'}, 'CODE', 'bg_user_code');
is( $cfg->{'ttcdir'}, '/tmp/approot/var/ttc', 'ttcdir');
is( $cfg->{'dir_run'}, '/var/run', 'dir_run');
is( $cfg->{'pidfile'}, '/var/run/parframe_7788.pid', 'pidfile');
is( $cfg->{'paraframe_group'}, 'staff', 'paraframe_group');
is( $cfg->{'time_zone'}, 'local', 'time_zone');
is( $cfg->{'umask'}, 7, 'umask');
is( $cfg->{'user_class'}, 'Para::Frame::User', 'user_class');


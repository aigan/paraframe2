package Para::Frame::Testing;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2017 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.012;
use warnings;

use Test::Warn;
use Storable qw( freeze dclone );
use FindBin;
use Cwd 'abs_path';

our $stdout;
our @got_warning;

use base qw( Exporter );
our @EXPORT = qw(flush_warnings);


BEGIN
{
    $SIG{__WARN__} = sub{ push @got_warning, shift() };

    open(SAVEOUT, ">&STDOUT");

    close( STDOUT );
    open STDOUT, ">/dev/null"       or die "Can't dup STDOUT: $!";
}

use Para::Frame;
use Para::Frame::Utils 'datadump';


my $approot = $FindBin::Bin . "/app";
my $pfdir = abs_path($FindBin::Bin.'/../share');

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

Para::Frame->configure($cfg_in);


my $cfg = $Para::Frame::CFG;
my $burner = Para::Frame::Burner->get_by_type('html');

Para::Frame::Site->add({
                        'code'        => 'test',
                        'name'        => 'Testing',
                        'webhome'     => '/test',
                        'webhost'     => 'frame.para.se',
                       });

#open STDOUT, ">/dev/null"       or die "Can't dup STDOUT: $!";
#open STDERR, ">/dev/null"       or die "Can't dup STDOUT: $!";

$|=1;
Para::Frame->startup;

open STDOUT, ">&", SAVEOUT      or die "Can't restore STDOUT: $!";

sub flush_warnings
{
    my( @warnings ) = @got_warning;
    @got_warning = ();
    return @warnings;
}


#########################

1;

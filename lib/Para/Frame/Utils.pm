#  $Id$  -*-perl-*-
package Para::Frame::Utils;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Utils class
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

=head1 NAME

Para::Frame::Utils - Utility functions for ParaFrame and applications

=cut

use strict;
use Carp qw(carp croak cluck confess shortmess);
use locale;
use Date::Manip;
use File::stat;
use File::Basename;
use Cwd 'abs_path';
use File::Spec;
use User::grent;
use User::pwent;
use IO::Dir;
use Data::Dumper;
use CGI;
use Digest::MD5  qw(md5_hex);
use Time::Seconds qw( ONE_MONTH ONE_DAY ONE_HOUR ONE_MINUTE );
use BerkeleyDB;
use IDNA::Punycode;
use Time::HiRes;
use Unicode::MapUTF8;
use LWP::UserAgent;
use HTTP::Request;
use Template::Exception;
use DateTime::Duration;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n"
	unless $Psi::QUIET; # houerly_active.pl

#    $Exporter::Verbose = 1;
}

use base qw( Exporter );
BEGIN
{
    @Para::Frame::Utils::EXPORT_OK

      = qw( in trim make_passwd random throw catch
            create_file create_dir chmod_tree chmod_file chmod_dir
            package_to_module module_to_package dirsteps
            compile passwd_crypt deunicode paraframe_dbm_open
            elapsed_time uri store_params clear_params add_params
            restore_params idn_encode idn_decode debug reset_hashref
            timediff extract_query_params fqdn retrieve_from_url
            get_from_fork );

}

use Para::Frame::Reload;

our %TEST; ### DEBUG
our $FQDN; # See fqdn()

=head1 FUNCTIONS

=cut


#######################################################################

=head2 in

  trim($string, @list)

Returns true if C<$string> is a part of C<@list> using string
comparsion

=cut

sub in ($@)
{
    my( $target ) = shift;

    for( my $i=0; $i <= $#_; $i++ )
    {
	return 1 if $target eq $_[$i];
    }
    return 0;
}


=head2 trim

  trim(\$string)

Removes preceding and proceding whitespace.

=cut

sub trim
{
    my $ref = shift;
    if( ref $ref )
    {
	return undef unless defined $$ref;
	$$ref =~ s/( ^ \s+ | \s+ $ )//gx;
	return $$ref;
    }
    else
    {
	return undef unless defined $ref;
	$ref =~ s/( ^ \s+ | \s+ $ )//gx;
	return $ref;
    }
}


=head2 make_passwd

  make_passwd()

Returns a string meant as a password, easy to remember but hard to guess.

=cut

sub make_passwd
{
    my @v = split '', "aeiouy";
    my @c = split '', "bdfghjklmnprstv";
    my $password = '';

    # Needed, since srand is called just in the parent process
    srand(time ^ $$);

    for (1..4)
    {
	$password .= $c[rand $#c];
	$password .= $v[rand $#v];
    }
    return $password;
}


=head2 random

  random()
  random($max)

Creates a integer number $x: 1 <= $x < $max

=cut

sub random
{
    my( $top ) = @_;

    return int rand( $top ) + 1;
}

=head2 throw

  throw( $error, $info, $output )
  throw( $exception )

$error is the name of the exception. $info tells whats went wrong.
$output shows where things get wrong, if its related to a place in a
block of text.

Use your own or one of the standard exceptions from
L<Para::Frame::Result/Exceptions>

=cut

sub throw
{
    my( $error, $info, $output ) = @_;
    local $" = ', ';

#    warn "Got thrown $error, $info";
    # die! die! die!
    if( UNIVERSAL::isa($error, 'Para::Frame::Result::Part'))
    {
	die $error;
    }
    elsif( UNIVERSAL::isa($error, 'Template::Exception') )
    {
	die $error;
    }
    elsif (defined $info)
    {
#	confess; ### DEBUG
#	warn "Creating an $error exception";
	die Template::Exception->new($error, $info, $output);
    }
    else
    {
	$error ||= 'error';
	die Template::Exception->new('undef', $error, $output);
    }
    # not reached
}


=head2 catch

  catch( $error )
  catch( $error, $output )
  catch( ['errtype1', 'errytpe2'], $output )

Returns (a true) L<Template::Exception> object if $error.

But if the input is a Para::Frame::Result::Part, use that instead,
since that is a cointainer of the error.

Appends $output to object.

If an arrayref of scalars is given, each scalar is compared to the
type of the exception object found in C<$@>.  Returns the object if
any of the types matches.  Throws an exception if none of the types
matches.

=head3 Example 1

  eval
  {
    ,,,
  };
  if( my $err = catch($@) )
  {
     die unless $err->type eq 'this';

     ... # Handle 'this' error
  }

=head3 Example 2

  eval
  {
    ,,,
  };
  if( my $err = catch(['this']) )
  {
     ... # Handle 'this' error
  }

=head3 Example 3

  eval
  {
    ,,,
  };
  if( my $err = catch(['this','that']) )
  {
     if( $err->type eq 'this' )
     {
        ... # Handle 'this' error
     }
     else
     {
        ... # Handle 'that' error
     }
  }


=cut

sub catch
{
    my( $error, $output ) = @_;

    return undef unless $error;
    if( UNIVERSAL::isa($error, 'Template::Exception') )
    {
	$error->text($output) if $output;
	return $error;
    }

    my $tests;

    if( ref $error eq 'ARRAY' ) # not object
    {
	# Se if error object matches any of these exceptions
	# Asume error lies in $@
	$tests = $error;
	$error = $@;
    }

    return undef unless $error;

    unless( UNIVERSAL::isa($error, 'Para::Frame::Result::Part') or
	    UNIVERSAL::isa($error, 'Template::Exception') )
    {
	my $type = 'undef';
	my $info = $error;

	if( ref $error eq 'ARRAY' )
	{
	    $type = $error->[0];
	    $info = $error->[1];
	}

	$error = Template::Exception->new( $type, $info, $output );
    }

    if( $tests )
    {
	foreach my $test ( @$tests )
	{
	    if( $error->type =~ /^$test(\.|$)/ )
	    {
		return $error;
	    }
	}
	die $error;
    }

    return $error;
}


=head2 create_dir

  create_dir( $dir )

Creates the directory, including parent directories.

All created dirs is chmod and chgrp to ritframe standard.

=cut

sub create_dir
{
    my( $dir, $params ) = @_;

#    warn "Gor dir: '$dir'\n";
    if( -e $dir )
    {
	$dir = abs_path($dir);
    }

    confess "Dir is now '$dir'" unless length $dir;

#    warn "Creating dir '$dir'\n";

    my $parent = dirname $dir;
    unless( -d $parent )
    {
	if( -e $parent )
	{
	    die "$parent is not a directory";
	}
	create_dir( $parent, $params );
    }
    if( -d $dir )
    {
	chmod_dir( $dir, $params );
    }
    else
    {
	if( -e $dir )
	{
	    confess "$dir is not a directory";
	}
	mkdir $dir, 0700;
	chmod_dir( $dir, $params );
    }
}


=head2 create_file

  create_file( $filename )
  create_file( $filename, $content )

Creates the file, including parent directories.

All created files is chmod and chgrp to ritframe standard.

=cut

sub create_file
{
    my( $file, $content, $params ) = @_;

    my $parent = dirname $file;
    create_dir($parent, $params);

    open( FILE, ">", $file) or die "Could not create file $file: $!\n";
    print FILE $content;
    close FILE;

    chmod_file( $file, $params );
}


=head2 chmod_tree

  chmod_tree( $dir );

Chmod and chgrp all files in dir tree to ritframe standard.
Chgrp file 

=cut

sub chmod_tree
{
    my( $dir, $params, $skip_re, $skip_h ) = @_;

#    warn "Chmod tree $dir\n"; ### DEBUG
    $dir = abs_path($dir);
    $skip_h ||= {};
    return if $skip_h->{$dir} ++;

#    warn Dumper $params;

    chmod_dir( $dir, $params );

    my $d = new IO::Dir $dir;
    foreach my $entry (  File::Spec->no_upwards( $d->read ) )
    {
	my $file = "$dir/$entry";

	if( -d $file )
	{
	    chmod_tree( $file, $params, $skip_re, $skip_h );
	}
	else
	{
	    chmod_file( $file, $params );
	}
    }
    $d->close;
}


=head2 chmod_file

  chmod_file( $filename, $mode, \%params )
  chmod_file( $filename, \%params )

Chgrp file according to $Para::Frame::CFG->{'paraframe_group'}.
Chmod file, using umask on 02777 for dirs and 0666 for files.

Using umask on $mode or $params{mode} if given

Using $params{umask} if given

=cut

sub chmod_file
{
    my( $file, $mode, $params ) = @_;

    $params ||= {};

    my $orig_umask = umask;

    if( ref $mode )
    {
	$params = $mode;
	$mode = undef;
    }

    my $new_umask = $params->{'umask'};
    my $umask = defined $new_umask ? $new_umask : $orig_umask;

    unless( $mode )
    {
	if( -d $file )
	{
	    $mode = $params->{'dirmode'} || $params->{'mode'} || 02777;
	}
	else
	{
	    $mode = $params->{'filemode'} || $params->{'mode'} || 0666;
	}
    }

    confess unless $file;
#    warn "Fix file $file\n"; ### DEBUG

    my $fstat = stat($file) or die "Could not stat $file: $!";
    my $fu = getpwuid( $fstat->uid ); # file user  obj
    my $fg = getgrgid( $fstat->gid ); # file group obj
    my $ru = getpwuid( $> );          # run  user  obj
    my $fun = $fu->name;              # file user  name
    my $fgn = $fg->name;              # file group name
    my $run = $ru->name;              # run  user  name
    my $pfg = getgrnam( $Para::Frame::CFG->{'paraframe_group'} );
    my $pfgn = $pfg->name;
    my $fmode = $fstat->mode & 07777; # mask of filetype

    die "file '$file' not found" unless -e $file;

    # Apply umask on $mode
    #
    $mode = $mode & ~ $umask;

    if( debug() > 3 )
    {
	debug(sprintf     "orig umask is 0%.4o", $orig_umask);
	if( defined $new_umask )
	{
	    debug(sprintf "umask set to  0%.4o", $new_umask);
	}
	debug(sprintf     "mode set to   0%.4o", $mode);
    }

    if( $fstat->gid == $pfg->gid and
	not $fmode ^ $mode & $mode )
    {
	return; # No change needed
    }

    # Yes. The sub &report_error is defined here. It's meant to only
    # be used by chmod_file, and will inherit all the variables
    # initiated above.

    my $report_error = sub
    {
	    my $msg = "File '$file' can not be modified\n";
	    $msg .= "  $!\n\n";
	    $msg .= "  The file is owned by $fun\n";
	    $msg .= "  The file is in group $fgn\n";
	    $msg .= sprintf("  The file has mode 0%.4o\n", $fmode);
	    $msg .= "  \n";
	    $msg .= "  You are running as user $run\n";

	    if( $> == 0 )
	    {
		$msg .= "  Do not run as root !!!\n";
	    }

	    # $f_mem = file is member in paraframe group
	    # $r_mem = user is member in paraframe group
	    my( $f_mem, $r_mem ); # Is either member in $pfg?
	    foreach my $gname ( @{ $pfg->members } )
	    {
		$f_mem ++ if $gname eq $fun;
		$r_mem ++ if $gname eq $run;
	    }
	    $f_mem ++ if $fu->gid == $pfg->gid;
	    $r_mem ++ if $ru->gid == $pfg->gid;

	    if( $f_mem )
	    {
#		$msg .= "  $fun belongs to group $pfgn\n";
	    }
	    else
	    {
		$msg .= "  $fun do NOT belong to group $pfgn\n";
	    }

	    if( $r_mem )
	    {
#		$msg .= "  $run belongs to group $pfgn\n";
	    }
	    else
	    {
		$msg .= "  $run do NOT belong to group $pfgn\n";
	    }

	    if( not $r_mem )
	    {
		$msg .= "  Run as $fun or add $run to group $pfgn\n";
	    }

	    if( $fgn ne $pfgn )
	    {
		$msg .= "  Change group of file to $pfgn. As root:\n";
		$msg .= "  chgrp $pfgn $file\n";
	    }

	    if( $fmode ^ $mode & $mode )
	    {
		$msg .= sprintf "  Change mode of file to 0%.4o.  As root:\n", $mode;
		$msg .= sprintf "  chmod 0%.4o $file\n", $mode;
	    }

	    if( $fgn ne $pfgn or $fmode ^ $mode & $mode )
	    {
		$msg .= "  Or if you want us to take care of if; as root:\n";
		my $dir = $file;
		$dir =~ s/\/[^\/]*$/\//;
		$msg .= "  chown -R $run $dir\n";
	    }


	    die $msg . "\n";
    };

    &$report_error if $> == 0; # Do not run as root

    unless( $fstat->gid == $pfg->gid )
    {
	unless( chown -1, $pfg->gid, $file )
	{
	    debug(0,"Tried to change gid");
	    &$report_error;
	}
    }

    if( $fmode ^ $mode & $mode ) # Is some of the bits missing?
    {
#    debug( sprintf "Tries to chmod file %s from 0%o to 0%o because we differ by %o", $file, $fmode,  $mode,($fmode ^ $mode & $mode));

	umask $new_umask if defined $new_umask;
	unless( chmod $mode, $file )
	{
	    umask $orig_umask if defined $new_umask;
	    debug(0,"Tried to chmod file");
	    &$report_error;
	}
	umask $orig_umask if defined $new_umask;
    }
}


=head2 chmod_dir

  chmod_dir( $dir )

Chmod and chgrp dir to ritframe standard.

=cut

sub chmod_dir
{
    my( $dir, $mode, $params ) = @_;

    $params ||= {};
    if( ref $mode )
    {
	$params = $mode;
	$mode = undef;
    }
    else
    {
	$params->{'mode'} = $mode;
    }

    return if $params->{'do_not_chmod_dir'};
    chmod_file( $dir, $params );
}


=head2 package_to_module

=cut

sub package_to_module
{
    my $package = shift;
    $package =~ s/::/\//g;
    $package .= ".pm";
    return $package;
}


=head2 module_to_package

=cut

sub module_to_package
{
    my $module = shift;
    $module =~ s/\//::/g;
    $module =~ s/\.pm$//;
    return $module;
}


=head2 uri_path

  uri_path()
  uri_path($url)

Returns the absolute path for the C<$url>. Defaults to the current
template.

=cut

sub uri_path
{
    my( $template ) = @_;

    my $req = $Para::Frame::REQ;

    $template ||= $req->template_uri;
    unless( $template =~ /^\// )
    {
	$template = URI->new_abs($template, $req->template_uri)->path;
    }
    return $template;
}

=head2 uri

  uri()
  uri( $url )
  uri( $url, \%params )

Creates a URL with query parameters separated by '&'.

$url should not include a '?'.  $url defaults to app->home.

=cut

sub uri
{
    my( $template, $attr ) = @_;

    my $req = $Para::Frame::REQ;

    throw('compilation', shortmess "Too many args for uri")
	if $attr and not ref $attr;

    $template ||= $Para::Frame::CFG->{'apphome'};

    my $extra = "";
    my @parts = ();
    foreach my $key ( keys %$attr )
    {
	my $value = $attr->{$key};
	if( UNIVERSAL::isa($value, 'ARRAY') )
	{
	    foreach my $val (@$value)
	    {
		push @parts, sprintf("%s=%s", $key, CGI->escape($val));
	    }
	}
	else
	{
	    push @parts, sprintf("%s=%s", $key, CGI->escape($value));
	}
    }
    my $query = join '&', @parts;
    $query and $query = '?'.$query;

#    warn "Returning URI $template.$query\n";
    return $template.$query;
}



###########################################

=head2 dirsteps

  dirsteps( $path, $base )

C<$base> is the website URL home path. Returns a list with all dirs
from C<$path> to the dir before C<$base>

=cut

sub dirsteps
{
    my( $path, $base ) = @_;

    unless( $path =~ /^\// and $path =~ /\/$/ )
    {
	confess "Invalid path: '$path'\n";
    }

    $base ||= '';
    if( $base =~ /\/$/ )
    {
	die "Invalid base '$base'\n";
    }

    my @step = ();

    my $length = length( $base ) || 1;

    while( length( $path ) > $length )
    {
	push @step, $path;
	$path =~ s/[^\/]+\/$//;
    }

#    debug("Returning dirsteps\n");
#    debug(join "",map(" - $_\n",@step));
#    debug(" with base $base\n");

    return @step;
}


=head2 compile

ciompile file

=cut


sub compile
{
    my( $filename ) = @_;

    my $mtime = 0;
    debug(0,"Compiling $filename");

    unless( defined $Para::Frame::Reload::COMPILED{$filename} )
    {
	$Para::Frame::Reload::COMPILED{$filename} = $^T;
    }

    if( my $realfilename = $INC{ $filename } )
    {
	my $stat;
	unless( $stat = stat($realfilename) )
	{
	    die "Can't locate $filename";
	}
	$mtime = $stat->mtime or die;
    }

    if( $mtime > $Para::Frame::Reload::COMPILED{$filename} )
    {
	debug(0,"New version of $filename detected !!!");
	delete $INC{$filename};
	$Para::Frame::Reload::COMPILED{$filename} = $mtime;
    }

    return require $filename;
}

=head1 passwd_crypt

  passwd_crypt( $password )

This function returns an encrypted version of the given string, uses
the current clients C-network IP as salt. The encrypted password will
be diffrent if the client comes from a diffrent net or subnet.

=cut

sub passwd_crypt
{
    my( $passwd ) = @_;

    my $ip = $Para::Frame::REQ->client_ip;
    $passwd or croak "Password missing";

    $ip =~ s/\.\d{1,3}$//; # accept changing ip within c-network

    debug(4,"using REMOTE_ADDR $ip");
    return md5_hex( $passwd, $ip );
}

sub deunicode
{
    if( $_[0] =~ /Ã/ ) # Could be unicode
    {
	$_[0] = Unicode::MapUTF8::from_utf8({-string=>$_[0],
					     -charset=>'ISO-8859-1'});
    }
    return $_[0];
}

sub paraframe_dbm_open
{
    my( $db_file ) = @_;

# #    warn "Creating BerkeleyDB::Env\n";
#     my $env = BerkeleyDB::Env->new(
# 				   -ErrFile  => '/tmp/psi_dbm_error.log',
# 				   );
# 

#    warn "Connecting to $db_file\n";
    my %db;
    tie( %db, 'BerkeleyDB::Hash',
	 -Filename => $db_file,
	 -Flags    => DB_CREATE,
#	 -Env      => $env,
	 )
	or die "Cannot open file '$db_file': $! $BerkeleyDB::Error\n";
#    warn "Returning handle\n";

    return \%db;
}

sub elapsed_time
{
    my( $secs ) = @_;

    if( UNIVERSAL::isa($secs, 'DateTime::Duration') )
    {
	my $deltas = $secs->deltas;
	$secs = 0;
	$secs += $deltas->{'months'}  * ONE_MONTH;
	$secs += $deltas->{'days'}    * ONE_DAY;
	$secs += $deltas->{'minutes'} * ONE_MINUTE;
	$secs += $deltas->{'seconds'};
    }

    my $c = Time::Seconds->new($secs);
    my $str;
    if( $c->days >= 1 )
    {
	$str .= int($c->days) . " dygn";
	$c -= int($c->days)*ONE_DAY;

	if( $c->hours >= 2 )
	{
	    $str .=  " och " . int($c->hours) . " timmar";
	}
	elsif( $c->hours >= 1 )
	{
	    $str .= " och en timma";
	}
	else
	{
	    $str .= " precis";
	}
    }
    elsif( $c->hours >= 1 )
    {
	if( $c->hours >= 2 )
	{
	    $str .=  int($c->hours) . " timmar";
	}
	else
	{
	    $str .= "1 timma";
	}
	$c -= int($c->hours)*ONE_HOUR;

	if( $c->minutes >= 2 )
	{
	    $str .=  " och " . int($c->minutes) . " minuter";
	}
	elsif( $c->minutes >= 1 )
	{
	    $str .= " och 1 minut";
	}
	else
	{
	    $str .= " precis";
	}
    }
    else
    {
	if( $c->minutes >= 2 )
	{
	    $str .= int($c->minutes) . " minuter";
	}
	elsif( $c->minutes >= 1 )
	{
	    $str .= "knappt 1 minut";
	}
	else
	{
	    $str .= "mindre än 1 minut";
	}	
    }

    return $str;
}


=head2 idn_decode

decode international domain names with punycode

=cut

sub idn_decode
{
    my( $domain ) = @_;

    cluck "Domain missing" unless $domain;

    if( $Para::Frame::Utils::TRANSCODED{ $domain } )
    {
	return $Para::Frame::Utils::TRANSCODED{ $domain };
    }

#    warn "  Decoding domain '$domain'\n";

    my @decoded;
    foreach my $part ( split /\./, $domain )
    {
	if( $part =~ /^xn--(.*)/i )
	{
	    $part = decode_punycode($1);
	}

	push @decoded, $part;
    }

    return $Para::Frame::Utils::TRANSCODED{ $domain } = join '.', @decoded;
}

=head2 idn_encode

encode international domain names with punycode

=cut

sub idn_encode
{
    my( $domain ) = @_;

#    warn "  Encoding domain '$domain'\n";

    my $port = "";
    if( $domain =~ s/(:\d+)$// )
    {
	$port = $1;
    }

    my @encoded;
    foreach my $part ( split /\./, $domain )
    {
#	warn "  part $part\n";
	if( $part =~ /[^A-Za-z0-9\-]/ )
	{
#	    warn "    encoding it\n";
	    $part = "xn--".encode_punycode($part);
	}

	push @encoded, $part;
    }

    $domain = join '.', @encoded;
    return $domain . $port;
}

=head2 store_params

Returns a hash with all the CGI query params

=cut

sub store_params
{
    my $q = $Para::Frame::REQ->q;

    my $state = {};
    foreach my $key ( $q->param() )
    {
	# $key could have many values
	$state->{ $key } = [ $q->param( $key ) ];
    }

#    warn "Returning state :".Dumper($state);
    return $state;
}

=head2 clear_params

  cleare_params(@list)
  clear_params

Clears the CGI query params given in list, or all params if no list
given

=cut

sub clear_params
{
    my $q = $Para::Frame::REQ->q;

    if( @_ )
    {
	foreach( @_ )
	{
	    $q->delete( $_ );
	}
    }
    else
    {
	$q->delete_all();
    }
}

=head2 add_params

  add_params(\%saved)

Adds to the CGI query with the params given in the hashref.

=cut

sub add_params
{
    my( $state ) = @_;

    my $q = $Para::Frame::REQ->q;

    foreach my $key ( keys %$state )
    {
	$q->param( $key, @{ $state->{$key} } );
    }
}

=head2 restore_params

  restore_params(\%saved)

Remove all the CGI query params and replace them with those in the
hashref given.

=cut

sub restore_params
{
    my( $state ) = @_;

    my $q = $Para::Frame::REQ->q;
    $q->delete_all();
    add_params($state);
}

=head2 debug

  debug($level, $message, $ident_delta)

Output debug info

=cut

sub debug
{
    my( $level, $message, $delta ) = @_;

    # Initialize here since DEBUG may be called before configure
    $Para::Frame::DEBUG  ||= 0;
    $Para::Frame::INDENT ||= 0;

    # Returns $message if given
    return "" if $Para::Frame::IN_STARTUP and $Para::Frame::QUIET_STARTUP and $level;
    return $Para::Frame::DEBUG unless defined $level;

    $delta ||= 0;
    $Para::Frame::INDENT += $delta if $delta < 0;

    unless( $message )
    {
	# Stupid regexp didn't take /^-?\d$/ !!!
	if( $level =~ /^(\d|-\d)$/ )
	{
	    $Para::Frame::INDENT += $level;
	    return "";
	}

	$message = $level;
	$level = 0;
    }

    if( $level < 0 )
    {
	$Para::Frame::INDENT += $level;
	$level = 0;
    }

    if( $Para::Frame::DEBUG >= $level )
    {
	my $prefix =  $Para::Frame::FORK ? "| $$: " : "";

	chomp $message;
	foreach(split /\n/, $message)
	{
	    warn $prefix . "  "x$Para::Frame::INDENT . $_ . "\n";
	}
    }

#    carp "Ident $delta" if $delta > 0;
    $Para::Frame::INDENT += $delta if $delta > 0;

#    if( $message =~ /^arc2 (\d+)/ )
#    {
#	confess if $TEST{$1}++ > 10;
#    }

    return $message . "\n";
}

sub reset_hashref
{
    my( $hashref, $params ) = @_;

    $params ||= {};

    foreach my $key ( keys %$hashref )
    {
	debug(2,"  Removing $key from hash");
	delete $hashref->{$key};
    }

    foreach my $key ( keys %$params )
    {
	$hashref->{$key} = $params->{$key};
    }

    return $hashref;
}


#########################################################

=head2 timediff

Returns the time since last usage of timediff, followd with the param
as text string.

=cut

sub timediff
{
    my $ts = $Para::Frame::timediff_timestamp;
    $Para::Frame::timediff_timestamp = Time::HiRes::time();
    return sprintf "%20s: %2.2f\n", $_[0], Time::HiRes::time() - $ts;
}


#########################################################

sub extract_query_params
{
    my $q = $Para::Frame::REQ->q;
    my $rec = {};

    foreach my $key (@_)
    {
	$rec->{$key} = $q->param($key);
    }

    return $rec;
}


#########################################################

=head2 fqdn

Gets the FQDN (fully qualified domain name). That is the hostname
followed by the domain name.  Tha availible perl modules fails for
me. ( Sys::Hostname and Net::Domain )

=cut

sub fqdn
{
    unless( $FQDN )
    {
	local $ENV{PATH} = '/usr/bin:/bin:/usr/sbin:/sbin'; # Paranoia.

	$FQDN = `(hostname  --fqdn) 2>/dev/null`;

	# remove garbage
	$FQDN =~ tr/\0\r\n//d;
    }
    return $FQDN;
}

=head2 retrieve_from_url

    retrieve_from_url( $url );

Gets the page/file in a fork.

Returns the page content on success or throws an action exception with
an explanation.

=cut

sub retrieve_from_url
{
    my( $url ) = @_;

    # We are doing this in the background and returns the result then
    # done.

    my $req = $Para::Frame::REQ;

    my $ua = LWP::UserAgent->new;
    my $lwpreq = HTTP::Request->new(GET => $url);

    my $fork = $req->create_fork;
    if( $fork->in_child )
    {
#	$fork->return("NAME=\"lat\" VALUE=\"11.9443\" NAME=\"long\" VALUE=\"57.7188\"");
	debug "About to GET $url";
	my $res = $ua->request($lwpreq);
	if( $res->is_success )
	{
	    $fork->return( $res->content );
	}
	else
	{
	    my $message = $res->message;
	    throw('action', "Failed to retrieve '$url' content: $message");

	    # TODO: Set up a better error response
#	    my $part = $req->result->exception('action', $message);
#	    $part->prefix_message("Failed to retrieve '$url' content");
#	    throw($part);
	}
    }

    return $fork->yield->message; # Returns the result from fork
}



=head2 get_from_fork

  get_from_fork(sub{ my_code })

Run given coderef in a fork an retrieve the results

=cut

sub get_from_fork
{
    my( $coderef ) = @_;

    my $req = $Para::Frame::REQ;

#    debug "About to fork";
    my $fork = $req->create_fork;
    if( $fork->in_child )
    {
#	debug "in child";
	$fork->return(&$coderef);
    }
#    debug "In parent: yield";
    return $fork->yield->message; # Returns the result from fork
}


=head2 validate

  validate( $value, $type )

Validate that a value is of the specified type

Returns true if validate and false otherwise

=cut

sub validate
{
    my( $value, $type ) = @_;

    die "not implemented";
}


1;


# maxof minof: use List::Util




=head1 SEE ALSO

L<Para::Frame>

=cut

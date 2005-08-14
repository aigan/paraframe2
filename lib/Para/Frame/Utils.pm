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
use Time::Seconds;
use BerkeleyDB;
use IDNA::Punycode;
use Time::HiRes;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n"
	unless $Psi::QUIET; # houerly_active.pl

#    $Exporter::Verbose = 1;
}

use base qw( Exporter );
BEGIN
{
    @Para::Frame::Utils::EXPORT_OK

      = qw( trim maxof minof make_passwd random throw
            catch create_file create_dir chmod_tree chmod_file
            chmod_dir package_to_module module_to_package dirsteps
            uri2file compile passwd_crypt deunicode paraframe_dbm_open
            elapsed_time uri store_params clear_params
            restore_params idn_encode idn_decode debug reset_hashref
	    inflect timediff );

}

use Para::Frame::Reload;


our %URI2FILE;


=head1 FUNCTIONS

=cut


#######################################################################

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


=head2 maxof

  maxof( @list )

Returns the numerical largest element.

=cut

sub maxof
{
    my $max = shift;

    while( my $val = shift )
    {
	$max = $val if $val > $max;
    }
    return $max;
}


=head2 minof

  minof( @list )

Returns the numerical smallest element.

=cut

sub minof
{
    my $min = shift;

    while( my $val = shift )
    {
	$min = $val if $val < $min;
    }
    return $min;
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

Creates a integer number $x: 1 <= $x <= $max

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

    # die! die! die!
    if (UNIVERSAL::isa($error, 'Template::Exception'))
    {
	die $error;
    }
    elsif (defined $info)
    {
#	confess; ### DEBUG
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

Returns (a true) L<Template::Exception> object if $error.  Appends
$output to object.

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

    if( $error and not UNIVERSAL::isa($error, 'Template::Exception') )
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

    if( $tests and $error )
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
    my( $dir ) = @_;

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
	create_dir( $parent );
    }
    if( -d $dir )
    {
	chmod_dir( $dir );
    }
    else
    {
	if( -e $dir )
	{
	    die "$dir is not a directory";
	}
	mkdir $dir, 02770;
	chmod_dir( $dir );
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
    my( $file, $content ) = @_;

    my $parent = dirname $file;
    create_dir($parent);

    open( FILE, ">", $file) or die "Could not create file $file: $!\n";
    print FILE $content;
    close FILE;

    chmod_file( $file );
}


=head2 chmod_tree

  chmod_tree( $dir );

Chmod and chgrp all files in dir tree to ritframe standard.

=cut

sub chmod_tree
{
    my( $dir, $skip_re, $skip_h ) = @_;

#    warn "Chmod tree $dir\n"; ### DEBUG
    $dir = abs_path($dir);
    $skip_h ||= {};
    return if $skip_h->{$dir} ++;

    chmod_dir( $dir );

    my $d = new IO::Dir $dir;
    foreach my $entry (  File::Spec->no_upwards( $d->read ) )
    {
	my $file = "$dir/$entry";

	if( -d $file )
	{
	    chmod_tree( $file, $skip_re, $skip_h );
	}
	else
	{
	    chmod_file( $file );
	}
    }
    $d->close;
}


=head2 chmod_file

  chmod_file( $filename )

Chmod and chgrp file to ritframe standard.

=cut

sub chmod_file
{
    my( $file, $mode ) = @_;

    $mode ||= 0660;

    confess unless $file;
#    warn "Fix file $file\n"; ### DEBUG

    my $fstat = stat($file);
    my $fu = getpwuid( $fstat->uid ); # file user  obj
    my $fg = getgrgid( $fstat->gid ); # file group obj
    my $ru = getpwuid( $> );          # run  user  obj
    my $fun = $fu->name;              # file user  name
    my $fgn = $fg->name;              # file group name
    my $run = $ru->name;              # run  user  name
    my $pfg = getgrnam( $Para::Frame::CFG->{'paraframe_group'} );
    my $pfgn = $pfg->name;

    die "file '$file' not found" unless -e $file;

    # Yes. The sub &report_error is defined here. It's meant to only
    # be used by chmod_file, and will inherit all the variables
    # initiated above.

    my $report_error = sub
    {
	    my $msg = "File '$file' can not be modified\n";
	    $msg .= "  $!\n\n";
	    $msg .= "  The file is owned by $fun\n";
	    $msg .= "  The file is in group $fgn\n";
	    $msg .= sprintf("  The file has mode %lo\n", $fstat->mode & 07777);
	    $msg .= "  \n";
	    $msg .= "  You are running as user $run\n";

	    if( $> == 0 )
	    {
		$msg .= "  Do not run as root !!!\n";
	    }

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
		$msg .= "  $fun belongs to group $pfgn\n";
	    }
	    else
	    {
		$msg .= "  $fun do NOT belong to group $pfgn\n";
	    }

	    if( $r_mem )
	    {
		$msg .= "  $run belongs to group $pfgn\n";
	    }
	    else
	    {
		$msg .= "  $run do NOT belong to group $pfgn\n";
	    }

	    if( $f_mem and not $r_mem )
	    {
		$msg .= "  Run as $fun or add $run to group $pfgn\n";
	    }

	    if( ($r_mem and not $f_mem) or ($fstat->mode & $mode ^ $mode) )
	    {
		$msg .= "  Change owner of file to $run.  As root:\n";
		$msg .= "  chown -R $run $file\n";
	    }


	    die $msg . "\n";
    };

    unless( $fstat->gid == $pfg->gid )
    {
	unless( chown -1, $pfg->gid, $file )
	{
	    debug(0,"Tried to change gid");
	    &$report_error;
	}
    }

    if( $fstat->mode & $mode ^ $mode ) # Is some of the bits missing?
    {
	unless( chmod $mode, $file )
	{
	    debug(0,"Tried to chmod file");
	    &$report_error;
	}
    }
}


=head2 chmod_dir

  chmod_dir( $dir )

Chmod and chgrp dir to ritframe standard.

=cut

sub chmod_dir
{
    my( $dir ) = @_;

    chmod_file( $dir, 02770 );
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

sub dirsteps
{
    my( $path, $base ) = @_;

    unless( $path =~ /^\// and $path =~ /\/$/ )
    {
	die "Invalid path: '$path'\n";
    }

    $base ||= '';
    if( $base =~ /\/$/ )
    {
	die "Invalid base '$base'\n";
    }

    my @step = ();

    while( length( $path ) > 1 )
    {
	push @step, $base . $path;
	$path =~ s/[^\/]+\/$//;
    }

#    warn "  Returning dirsteps @step\n";
    return @step, '/';
}

sub uri2file
{
    my( $uri, $file, $req ) = @_;

    # This will return file without '/' for dirs
#    warn "  Get filename for uri $uri\n";

    $req ||= $Para::Frame::REQ;
    my $key = $req->host_name . $uri;

    if( $file )
    {
	return $URI2FILE{ $key } = $file;
    }

    if( my $file = $URI2FILE{ $key } )
    {
	return $file;
    }

#    warn "    From client\n";
    $req->send_code( 'URI2FILE', $uri );
    $file = Para::Frame::get_value( $req->client );

    $URI2FILE{ $key } = $file;
    return $file;
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
	$mtime = stat($realfilename)->mtime
	  or die "Lost contact with $realfilename";
    }

    if( $mtime > $Para::Frame::Reload::COMPILED{$filename} )
    {
	debug(0,"New version of $filename detected !!!");
	delete $INC{$filename};
	$Para::Frame::Reload::COMPILED{$filename} = $mtime;
    }

    return require $filename;
}


sub passwd_crypt
{
    my( $passwd ) = @_;

    my $ip = $Para::Frame::REQ->client_ip;

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

    my %db;

    tie( %db, 'BerkeleyDB::Hash',
	 -Filename => $db_file,
	 -Flags    => DB_CREATE )
	or die "Cannot open file '$db_file': $! $BerkeleyDB::Error\n";

    return \%db;
}

sub elapsed_time
{
    my( $secs ) = @_;

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
    foreach my $key ( keys %$state )
    {
	$q->param( $key, @{ $state->{$key} } );
    }
}

=head2 debug

  debug($level, $message, $ident_delta)

Output debug info

=cut

sub debug
{
    my( $level, $message, $delta ) = @_;

    # Returns $message if given

    return $Para::Frame::DEBUG unless defined $level;

    $delta ||= 0;
    $Para::Frame::INDENT += $delta if $delta < 0;

    unless( $message )
    {
	if( $level =~ /^-?\d$/ )
	{
	    $Para::Frame::INDENT += $level;
	    return;
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
	warn $prefix . "  "x$Para::Frame::INDENT . $message . "\n";
    }

    $Para::Frame::INDENT += $delta if $delta > 0;

    return $message . "\n";
}

sub reset_hashref
{
    my( $hashref, $params ) = @_;

    $params ||= {};

    foreach my $key ( keys %$hashref )
    {
	debug(1,"  Removing $key from hash");
	delete $hashref->{$key};
    }

    foreach my $key ( keys %$params )
    {
	$hashref->{$key} = $params->{$key};
    }

    return $hashref;
}

sub inflect # inflection = böjning
{
    my( $number, $none, $one, $many ) = @_;

    # Support calling with or without the $none option

    if( $many )
    {
	# If called with %d, interpolate the number
	$many =~ s/\%d/$number/;
    }
    else
    {
	$many = $one;

	# If called with %d, interpolate the number
	$many =~ s/\%d/$number/;

	$one = $none;
	$none = $many;
    }


    if( $number == 0 )
    {
	return $none;
    }
    elsif( $number == 1 )
    {
	return $one;
    }
    else
    {
	# Also for negative numbers
	return $many;
    }
}

sub timediff
{
    my $ts = $Para::Frame::timediff_timestamp;
    $Para::Frame::timediff_timestamp = Time::HiRes::time();
    return sprintf "%20s: %2.2f\n", $_[0], Time::HiRes::time() - $ts;
}

1;

=head1 SEE ALSO

L<Para::Frame>

=cut

#  $Id$  -*-cperl-*-
package Para::Frame::File;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2006-2008 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::File - Represents a file in the site

=head1 DESCRIPTION

See also L<Para::Frame::Dir> and L<Para::Frame::Template>.

=cut

use strict;
use utf8; # Ã used in file

use Encode;
use Carp qw( croak confess cluck );
use File::stat; # exports stat
use Scalar::Util qw(weaken);
use Number::Bytes::Human qw(format_bytes);
use File::Slurp qw(slurp); # May export read_file, write_file, append_file, overwrite_file, read_dir
use Cwd 'abs_path';
use File::Copy qw(); # NOT exports copy
use File::Remove;
#use File::MimeInfo qw(); # NOT exports mimetype()

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";

    #### A hack for using this code in bytes mode
    package File::MimeInfo;
    use bytes;
    my $filename = "File/MimeInfo.pm";
  ITER:
    {
	foreach my $prefix (@INC)
	{
	    my $realfilename = "$prefix/$filename";
	    if( -f $realfilename )
	    {
		$INC{$filename} = $realfilename;
		my $file = File::Slurp::read_file( $realfilename );
		eval $file;
		last ITER;
	    }
	}
	die "Can't find $filename in \@INC";
    }
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump catch chmod_file create_dir deunicode validate_utf8 );
use Para::Frame::List;
use Para::Frame::Dir;
use Para::Frame::Template;
use Para::Frame::Image;

#######################################################################

=head2 new

  Para::Frame::File->new( $params )

Creates a File object. It should be initiated before used. (Done by
the methods here.)

params:

  hide
  req
  filename
  url
  site
  file_may_not_exist

=cut

sub new
{
    my( $this, $args ) = @_;
    my $class = ref($this) || $this;
    my $req = $Para::Frame::REQ;

    $args ||= {};
    my $DEBUG = 0;

    debug "New file with ".datadump($args,1) if $DEBUG;

    my $sys_in = $args->{'filename'};
    my $url_in = $args->{'url'};
    my $site_in = $args->{'site'};

    my $key = $sys_in;
    if( $key )
    {
	confess "Not a string: $sys_in" if ref $sys_in;
    }
    else
    {
	confess "Missing site" unless $site_in;
	if( ref $url_in )
	{
	    $url_in = $url_in->url_path_slash;
	}
	else
	{
	    # Clear out query part, if existing
	    $url_in =~ s/(\?|#).*//;
	}
	$key = $site_in->code . $url_in;
    }
    # Key should be the same with or without trailing slash
    $key =~ s/\/$//;

 SHORTCUT:
    {
	if( my $file = $Para::Frame::File::Cache{ $key } )
	{
	    if( $class ne 'Para::Frame::File' )
	    {
		if( ref($file) ne $class )
		{
		    debug "Stored file not of the right class";
		    last SHORTCUT;
		}
	    }

	    if( $DEBUG )
	    {
		if( $file->exist )
		{
		    debug "Got from CACHE: $key - exist";
		}
		else
		{
		    debug "Got from CACHE: $key";
		}
	    }

	    return $file;
	}
    }

    debug "--------> CREATING file $key" if $DEBUG;

    my $file = bless
    {
     'url_norm'       => undef,
     'sys_norm'       => undef,
     'url_name'       => undef, # without trailing slash
     'sys_name'       => undef, # without trailing slash
     'site'           => undef,
     'initiated'      => 0,
     'hide'           => undef, # TODO: remove this
     'exist'          => undef,
     'dirsteps'       => undef,
    }, $class;

    # TODO: This value can't be changed since it's a shared cache
    $file->{'hide'} = $args->{'hide'} || qr/(^\.|^CVS$|\#$|~$)/;

    my $may_not_exist = $args->{'file_may_not_exist'} || 0;
    my $exist;


    my( $url_norm, $sys_norm, $url_name, $sys_name, $site );

    if( $url_in )
    {
	$url_name = $url_in;
	$url_name =~ s/\/$//; # No trailing slash

	if( $sys_in )
	{
	    die "Don't specify filename with uri";
	}
	elsif( UNIVERSAL::isa( $class, "Para::Frame::Dir" ) )
	{
	    if( $url_name =~ /\.(tt|html?|css)\/?$/ )
	    {
		confess "File $url_name doesn't look like a dir";
	    }
	    $url_norm = $url_name . '/';
	}
	else
	{
	    # Taken as dir if ending with slash
	    $url_norm = $url_in;
	}

	# TODO: Use URL for extracting the site
	my $site = $file->set_site( $site_in || $req->site );

	# $sys_name is without trailing slash
	$sys_name = $site->uri2file($url_in, undef, $may_not_exist );

	# This may give a dir to file translation. Only keep dir part
	if( $url_in =~ /\/$/ )
	{
	    unless( $sys_name =~ /\/$/ )
	    {
		debug "URL $url_in (DIR) was mapped to file $sys_name";
		$sys_name =~ s/\/[^\/]+$/\//;
		debug "  Remapping to $sys_name";
	    }
	}

	$sys_name =~ s/\/$//;

	# $sys_norm is undef
    }
    elsif( $sys_in )
    {
	$sys_name = $sys_in;
	$sys_name =~ s/\/$//; # No trailing slash

	# $sys_norm is undef
    }
    else
    {
	confess "Filename missing ($class): ".datadump($args);
    }

    # $sys_name is defined
    # $sys_norm is undef

    debug "Constructing $sys_name" if $DEBUG;
    if( $sys_name =~ m(//) )
    {
	cluck "Sysname $sys_name has double slashes";
    }

    if( -r $sys_name )
    {
	$exist = 1;

# ... This is bad for sites with symlinks!
#
#	# Resolve relative parts in the path
#	$sys_name = abs_path( $sys_name );

	debug "File $sys_name exist" if $DEBUG;

	if( -d $sys_name or
	    UNIVERSAL::isa( $class, "Para::Frame::Dir" ) )
	{
	    if( $sys_name =~ /\.(tt|html?|css)\/?$/ )
	    {
		confess "File $sys_name doesn't look like a dir";
	    }

	    if( -d $sys_name )
	    {
		$sys_norm = $sys_name . '/';
		if( $url_name )
		{
		    $url_norm = $url_name . '/';
		}

		unless( UNIVERSAL::isa( $class, "Para::Frame::Dir" ) )
		{
		    unless( $class eq 'Para::Frame::File' )
		    {
			croak "The file $sys_name is a dir (not a $class)";
		    }
		    bless $file, 'Para::Frame::Dir';
		}
	    }
	    else
	    {
	        cluck"The file $sys_name is not a dir";
		bless $file, 'Para::Frame::File';
	    }
	}

	unless( -d $sys_name )
	{
	    $sys_name =~ s/\/$//;
	    $sys_norm = $sys_name;

	    # Compare with $url_norm
	    if( $url_norm and $url_norm =~ /\/$/ )
	    {
		cluck "The URL $url_norm ($sys_norm) is not a dir";
		$url_norm =~ s/\/$//;
	    }
	}

	# $sys_norm is defined
    }
    else
    {
	$exist = 0;

	if( not -e $sys_name )
	{
	    unless( $may_not_exist )
	    {
		confess "The file $sys_name is not found";#.datadump([$sys_name, $args]);
	    }
	}
	elsif( not -r $sys_name )
	{
	    confess "The file $sys_name is not readable";
	}

	debug "File $sys_name doesn't exist" if $DEBUG;

	# determine if dir by class or input
	if( $class eq 'Para::Frame::File' )
	{
	    if( $url_norm and $url_norm =~ /([^\/]*)\/$/ )
	    {
		my $preslash = $1;

		if( $url_norm =~ /\.(tt|html?|css)\/?$/ )
		{
		    confess "File $url_norm doesn't look like a dir";
		}

		# There may have been a mapping from dir to file
		debug "sys_name: $sys_name";
		debug "preslash: $preslash";
		if( $preslash and $sys_name =~ /\b$preslash$/ )
		{
		    debug "Blessing as a dir";
		    bless $file, 'Para::Frame::Dir';
		    $sys_norm = $sys_name . '/';
		}
		else
		{
		    $sys_norm = $sys_name;
		}
	    }
	    else
	    {
		$sys_norm = $sys_name;
	    }
	}
	elsif( UNIVERSAL::isa( $class, "Para::Frame::Dir" ) )
	{
	    if( $sys_name =~ /\.(tt|html?|css)\/?$/ )
	    {
		confess "File $sys_name doesn't look like a dir";
	    }

	    $sys_norm = $sys_name . '/';
	}
	else
	{
	    $sys_norm = $sys_name;
	}

	# $sys_norm is defined
    }

    $file->{'exist'} = $exist;
    $file->{'sys_norm'} = $sys_norm; # With dir trailing slash
    $file->{'sys_name'} = $sys_name; # Without dir trailing slash

    # Validate site
    if( my $site = $file->site )
    {
	# Check that url is part of the site
	my $home = $site->home_url_path;
	unless( $url_name =~ /^$home/ )
	{
	    confess sprintf "URL '%s' is out of bound for site %s: %s", $url_in, $site->name, datadump($args,1);
	}

	$file->{'url_norm'} = $url_norm;  # With dir trailing slash
	$file->{'url_name'} = $url_name;  # Without dir trailing slash
    }
    else
    {
	# Place in site based on sys_path
	debug "Try to place in site" if $DEBUG;

	# If we are going to check all the registred sites, we must be
	# sure that those sites realy are handled by this paraframe
	# server and that they are set up correctly. If not; we will
	# get dangling subrequests and this request will freeze.

	# TODO: Check all registred sites at startup to make sure that
	# they are functional.

	my @check_sites = ();
	if( $Para::Frame::CFG->{'site_autodetect'} )
	{
	    @check_sites = values %Para::Frame::Site::DATA;
	}

	if( my $req_site = $req->site )
	{
	    # Check current site first
	    unshift @check_sites, $req_site;
	}

	foreach my $site_maby ( @check_sites )
	{
	    my $sys_home = $site_maby->home->sys_path_slash;
	    debug "Checking $sys_home" if $DEBUG;
	    if( $file->{'sys_norm'} =~ /^$sys_home(.*)/ )
	    {
		# May not be a correct translation
		my $url_norm = $site_maby->home->url_path_slash.$1;
		debug "Translating $url_norm" if $DEBUG;
		my $sys_name = $site_maby->uri2file($url_norm, undef, $may_not_exist);
		$sys_name =~ s/\/$//;

		unless( $sys_name eq $file->{'sys_name'} )
		{
		    debug "Path translation mismatch: $sys_name != $file->{sys_name}! Skipping this site";
		    next;
		}

		my $url_name = $url_norm;
		$url_name =~ s/\/$//; # No trailing slash

		$file->{'url_norm'} = $url_norm;  # With dir trailing slash
		$file->{'url_name'} = $url_name;  # Without dir trailing slash
		$file->{'site'}     = $site_maby;

		last;
	    }
	}
    }

    # Bless into Para::Frame::Template if it is a template
    if( $class eq 'Para::Frame::File' )
    {
	if( my $ext = $file->suffix )
	{
	    if( my $burner = Para::Frame::Burner->get_by_ext($ext) )
	    {
		bless $file, "Para::Frame::Template";
		$args->{'burner'} = $burner;
	    }
	    else
	    {
		my $mtype_base = $file->mimetype_base;
		if( $mtype_base eq 'image' )
		{
		    bless $file, "Para::Frame::Image";
		}
	    }
	}
    }

    if(  my $cached = $Para::Frame::File::Cache{$file->{'sys_name'}} )
    {
	$Para::Frame::File::Cache{ $key } = $cached;
	debug 2, "---> GOT FROM CACHE";

	# Upgrade with URL info if given
	if( $file->{'url_name'} and not $cached->{'url_name'} )
	{
	    debug "---> EXTENDED WITH URL INFO";

	    $cached->{'url_name'} = $file->{'url_name'};
	    $cached->{'url_norm'} = $file->{'url_norm'};
	    $cached->{'site'}     = $file->{'site'};
	}

	if( ref($file) ne ref($cached) )
	{
	    my $class_from = ref($cached);
	    my $class_to   = ref($file);
	    debug "Changing class of cached file from $class_from to $class_to";

	    # In case of dir
	    $cached->{'url_norm'} = $file->{'url_norm'};
	    $cached->{'sys_norm'} = $file->{'sys_norm'};
	    bless( $cached, ref($file) );
	}

	$cached->{'initiated'} = 0;

	$file = $cached;
    }
    else
    {
	$Para::Frame::File::Cache{$file->{'sys_name'}} =
	  $Para::Frame::File::Cache{ $key } = $file;
    }

    $file->initialize( $args );

    debug "CREATED ".$file->sysdesig if $DEBUG;

    return $file;
}

#######################################################################

=head2 reset

=cut

sub reset
{
    my( $f ) = @_;

#    debug "Resetting ".$f->sysdesig;

    $f->{'initiated'} = 0;
    $f->initiate;

#    debug "Now       ".$f->sysdesig;
}


#######################################################################

=head2 new_sysfile

=cut

sub new_sysfile
{
    return $_[0]->new({'filename'=>$_[1]});
}

#######################################################################

=head2 new_possible_sysfile

=cut

sub new_possible_sysfile
{
    return $_[0]->new({'filename'=>$_[1], 'file_may_not_exist'=>1});
}

#######################################################################

=head2 site

=cut

sub site
{
    return $_[0]->{'site'};
}


#######################################################################

=head2 req

=cut

sub req
{
    return $Para::Frame::REQ;
}

#######################################################################

=head2 initiate

=cut

sub initiate
{
    my( $f ) = @_;

    my $name = $f->sys_path;
    my $st = stat($name);

    unless( $st )
    {
	debug 2, "Couldn't find $name!";
	$f->{initiated} = 0;
	$f->{'exist'} = 0;
	return 0;
    }

    my $mtime = $st->mtime;

    if( $f->{initiated} )
    {
	return 1 unless $mtime > $f->{mtime};
    }

#    debug "Initiating $name";

    $f->{'exist'} = 1;
    $f->{mtime} = $mtime;
    $f->{readable} = -r _;
    $f->{writable} = -w _;
    $f->{executable} = -x _;
    $f->{owned} = -o _;
    $f->{size} = -s _;
    $f->{plain_file} = -f _;
    $f->{directory} = -d _;
    $f->{named_pipe} = -p _;
    $f->{socket} = -S _;
    $f->{block_special_file} = -b _;
    $f->{character_special_file} = -c _;
    $f->{tty} = -t _;
    $f->{setuid} = -u _;
    $f->{setgid} = -g _;
    $f->{sticky} = -k _;
    $f->{ascii} = -T _;
    $f->{binary} = -B _;

    $st = lstat($name);
    if( -l _ )
    {
	$f->{symbolic_link} = readlink($name);
    }

    return $f->{initiated} = 1;
}

#######################################################################

=head2 set_depends_on

=cut

sub set_depends_on
{
    my( $tmpl, $depends ) = @_;

    unless( ref $depends eq 'ARRAY' )
    {
	confess "Wrong input: ".datadump( $depends );
    }

    $tmpl->{'depends_on'} = $depends;
}


#######################################################################

=head2 is_updated

Checks in the templates this has been compiled from has changed

=cut

sub is_updated
{
    my( $tmpl ) = @_;

    if( $tmpl->exist )
    {
	$tmpl->{'depends_on'} ||= [];
      SRC:
	foreach my $src (@{$tmpl->{'depends_on'}})
	{
	    if( $tmpl->mtime_as_epoch >= $src->mtime_as_epoch )
	    {
		next SRC;
	    }
	    return 1;
	}
	return 0;
    }
    return 1;
}

#######################################################################

=head2 initialize

=cut

sub initialize
{
    return 1;
}

#######################################################################

=head1 Accessors

Prefix url_ gives the path of the dir in http on the host

Prefix sys_ gives the path of the dir in the filesystem

No prefix gives the path of the dir relative the site root in url_path

path_base excludes the suffix of the filename

path gives the preffered URL for the file

For dirs: always exclude the trailing slash, except for path_slash

=cut

#######################################################################

=head2 parent

Same as L</dir>, except that if the template is the index, we will
instead get the parent dir.

=cut

sub parent
{
    my( $f ) = @_;

    my $site = $f->site or confess "Not implemented";

    if( $f->{'url_norm'} =~ /\/$/ )
    {
	debug 2, "Getting parent for page index";
	return $f->dir->parent;
    }
    else
    {
	debug 2, "Getting dir for page";
	return $f->dir;
    }
}


#######################################################################

=head2 dir

  $f->dir()

  $f->dir( \%params )

Gets the directory for the file.

Returns self if file is a directory.

See also L<Para::Frame::Dir/parent>

params:

none

Returns

May not return a dir. It may be another type of file in the case then
this file was hypothetical.

A L<Para::Frame::Dir>

=cut


sub dir
{
    my( $f, $args ) = @_;

    $args ||= {};

    unless( $f->{'dir'} )
    {
#	debug "Finding dir for file ".$f->sysdesig;
	unless( $f->exist )
	{
	    $args->{'file_may_not_exist'} = 1;
#	    debug "  may not exist";
	}

	if( $f->site )
	{
	    my $url_path_slash = $f->url_path_slash;
	    $url_path_slash =~ /^(.*\/)[^\/]*$/
	      or confess "Strange path $url_path_slash";

	    if( $url_path_slash eq $1 )
	    {
		return $f;
	    }
	    else
	    {
#		debug "  Dir part of path is $1";
		$f->{'dir'} = Para::Frame::Dir->new({site => $f->site,
						     url  => $1,
						     %$args,
						    });
	    }
	}
	else
	{
	    my $sys_path_slash = $f->sys_path_slash;
	    $sys_path_slash =~ /^(.*\/)[^\/]*$/
	      or confess "Strange path $sys_path_slash";

	    if( $sys_path_slash eq $1 )
	    {
		return $f;
	    }
	    else
	    {
		$f->{'dir'} = Para::Frame::Dir->new({'filename' => $1,
						     %$args,
						    });
	    }
	}
    }

    return $f->{'dir'};
}

#######################################################################

=head2 dir_url_path

The URL path to the template, excluding the filename, relative the site
home, begining but not ending with a slash. May be an empty string.

=cut

sub dir_url_path
{
    my( $f ) = @_;
    my $path = $f->url_path or confess "Site not given";
    $path =~ /^(.*?)\/[^\/]*$/;
    return $1||'';
}


#######################################################################

=head2 name

The template filename without the path.

For dirs, the dir name without the path and without trailing slash.

=cut

sub name
{
    $_[0]->sys_path =~ /\/([^\/]+)\/?$/
	or die "Couldn't get filename from ".$_[0]->sys_path;
    return $1;
}

#######################################################################

=head2 name_slash

The template filename without the path.

For dirs, the dir name without the path but with the trailing slash.

=cut

sub name_slash
{
    $_[0]->sys_path_slash =~ /\/([^\/]+\/?)$/
	or die "Couldn't get filename from ".$_[0]->sys_path;
    return $1;
}

#######################################################################


=head2 path

The preffered URL for the file, relative the site home, begining with
a slash. And for dirs, not ending with a slash.

=cut

sub path
{
    my( $f ) = @_;

    my $site = $f->site or confess "No site given";
    my $home = $site->home_url_path;
    my $url_path = $f->url_path;
    my( $site_url ) = $url_path =~ /^$home(.*?)$/
      or confess "Couldn't get site_url from $url_path under $home";
    return $site_url;
}


#######################################################################

=head2 path_slash

The preffered URL for the file, relative the site home, begining with
a slash. And for dirs, ending with a slash.

=cut

sub path_slash
{
    my( $f ) = @_;

    my $site = $f->site or confess "No site given";
    my $home = $site->home_url_path;
    my $url_path = $f->url_path_slash;
    my( $site_url ) = $url_path =~ /^$home(.+?)$/
      or confess "Couldn't get site_url from $url_path under $home";
    return $site_url;
}

#######################################################################



=head2 set_site

  $f->set_site( $site )

Sets the site to use for this request.

C<$site> should be the name of a registred L<Para::Frame::Site> or a
site object.

The site must use the same host as the request.

The method works similarly to L<Para::Frame::Request/set_site>

Returns: The site object

=cut

sub set_site
{
    my( $f, $site_in ) = @_;

    $site_in or confess "site param missing";

    my $site = $Para::Frame::CFG->{'site_class'}->get( $site_in );

    # Check that site matches the client
    #
    if( my $req = $f->req )
    {
	unless( $req->client =~ /^background/ )
	{
	    if( my $orig = $req->original )
	    {
		unless( $orig->site->host eq $site->host )
		{
		    my $site_name = $site->name;
		    my $orig_name = $orig->site->name;
		    debug "Host mismatch";
		    debug "orig site: $orig_name";
		    debug "New name : $site_name";
#		    confess "set_site called";
		}
	    }
	}
    }

    return $f->{'site'} = $site;
}


#######################################################################

=head2 sys_path

The path from the system root. Excluding the last '/' for dirs.

=cut

sub sys_path
{
    return $_[0]->{'sys_name'};
}


#######################################################################

=head2 sys_path_slash

The path from the system root. Including the last '/' for dirs.

=cut

sub sys_path_slash
{
    return $_[0]->{'sys_norm'};
}


#######################################################################

=head2 sys_base

The path to the template from the system root, including the filename.
But excluding the suffixes of the file along with the dots. For Dirs,
excluding the trailing slash.

=cut

sub sys_base
{
    my( $page ) = @_;

    my $path = $page->sys_path;
    $path =~ m/ ^ (.*?)(\.\w\w)?\.\w{2,3} $ /x
      or confess "Couldn't get base from $path";
    return $1;
}


#######################################################################

=head2 url

Returns the L<URI> object, including the scheme, host and port.

=cut

sub url
{
    my( $page ) = @_;

    my $site = $page->site or confess "No site given";
    my $url_string = sprintf("%s://%s%s",
			     $site->scheme,
			     $site->host,
			     $page->{url_norm});

    return Para::Frame::URI->new($url_string);
}


#######################################################################


=head2 url_path

The URL for the file in http on the host. For dirs, excluding trailing
slash.


=cut

sub url_path
{
    return $_[0]->{'url_name'} or confess "No site given";
}


#######################################################################


=head2 url_path_slash

This is the PREFERRED URL for the file in http on the host. For dirs,
including trailing slash.

=cut

sub url_path_slash
{
    return $_[0]->{'url_norm'} or confess "No site given";
}


#######################################################################

=head2 base

The path to the template, including the filename, relative the site
home, begining with a slash. But excluding the suffixes of the file
along with the dots.

Not valid for dirs

=cut

sub base
{
    my( $f ) = @_;

    my $site = $f->site or confess "No site given";
    my $home = $site->home_url_path;
    my $target;
    if( $f->is_dir )
    {
	$target = $f->target->url_path;
    }
    else
    {
	$target = $f->url_path;
    }
    $target =~ /^$home(.*?)(\.\w\w)?\.\w{2,4}$/
      or confess "Couldn't get base from $target under $home";
    return $1;
}

#######################################################################

=head2 base_name

The filename, but excluding the suffixes of the file
along with the dots. For Dirs, excluding the trailing slash.

Not valid for dirs

=cut

sub base_name
{
    my( $f ) = @_;

    my $template = $f->name;
    if( $template =~ /^(.*?)(\.\w\w)?\.\w{2,4}$/ )
    {
	return $1;
    }
    else
    {
	return $template;
    }
}


#######################################################################

=head2 suffix

The suffix (extension) part of the file, exclusive the dot.

Returns the last part as a string.  The file C</index.sv.tt> will
return C<tt>.

For dirs or for files without a suffix, we will return '';

=cut

sub suffix
{
    my( $file ) = @_;

    $file->{'sys_norm'} =~ /\.([^\.\/]+)$/
      or return "";
    return $1;
}


#######################################################################

=head2 langcode

=cut

sub langcode
{
    my( $file ) = @_;

    $file->{'sys_norm'} =~ /([^\.\/]+)\.[^\.\/]+$/
      or return "";
    return $1;
}


#######################################################################

=head2 chmod

  $f->chmod()

  $f->chmod( $mode, \%args )

Calls L<Para::Frame::Utils/chmod_file>

=cut

sub chmod
{
    my( $file ) = shift;
    return chmod_file($file->sys_path, @_);
}

#######################################################################

=head2 vcs_version

  $file->vcs_version()

VCS stands for Version Control System.

Gets the current version string of this file.

May support other systems than CVS.

Returns: the scalar string

=cut

sub vcs_version
{
   my( $file ) = @_;

   my $dir = $file->dir;
   my $name = $file->name;

   if( $dir->has_dir('CVS') )
   {
       my $cvsdir = $dir->get('CVS');
       my $fh = new IO::File;
       my $filename = $cvsdir->sys_path.'/Entries';
#       debug "Checking $filename";
       $fh->open( $filename ) or die "Failed to open '$filename': $!\n";
       while(<$fh>)
       {
	   if( m(^\/(.+?)\/(.+?)\/) )
	   {
	       next unless $1 eq $name;
#	       debug "  Returning $2";
	       return $2;
	   }
       }
#       debug "  No version found";
   }
   return undef;
}

#######################################################################

=head2 filesize

  $file->filesize()

=cut

sub filesize
{
   my( $file ) = @_;

   my $sys_path = $file->sys_path;
   debug "Statting $sys_path";

   return format_bytes(stat($file->sys_path)->size);
}

#######################################################################

=head2 desig

=cut

sub desig
{
    my( $file ) = @_;

    my $sys_path = $file->{'sys_norm'} || '<unknown>';
    my $path_slash = $file->site ? $file->path_slash : '<unknown>';
    return sprintf "%s (%s)", $sys_path, $path_slash;
}


#######################################################################

=head2 sysdesig

=cut

sub sysdesig
{
    my( $file ) = @_;

    my $sys_path = $file->{'sys_norm'} || '<unknown>';
    my $path_slash = $file->site ? $file->path_slash : '<unknown>';
    my $date_str = $file->exist ? $file->mtime : '<not found>';
    return sprintf "%s (%s) %s", $sys_path, $path_slash, $date_str;
}


#######################################################################

=head2 target

The corresponding template URL for this file.  This will give
C</index.en.tt> for C</>.

It may not be cached between requests since the language may change.

args:

  lang_code
  language

=cut

sub target
{
    my( $file, $args ) = @_;

    $args ||= {};

#    debug "Finding the target for ".$file->desig." with ".datadump($args,2);

    my $target = $file->{'url_norm'} || $file->{'sys_norm'};

    if( $target =~ /\/$/ )
    {
	# Target indicates a dir. Make it so
	$target .= "index.tt";
    }

    if( my $site = $file->site )
    {
	$args->{'site'} = $site;
	$args->{'url'} = $target;
    }
    else
    {
	$args->{'filename'} = $target;
    }

    $args->{'file_may_not_exist'} = 1;

    return Para::Frame::File->new( $args );
}


#######################################################################

=head2 target_with_lang

=cut

sub target_with_lang
{
    my( $file, $args ) = @_;

    $args ||= {};

#    debug "Finding the target for ".$file->desig." with ".datadump($args,2);

    my $target = $file->{'url_norm'} || $file->{'sys_norm'};

    if( $target =~ /\/$/ )
    {
	# Target indicates a dir. Make it so
	$target .= "index.tt";
    }

    # The language
    my $code = $args->{'lang_code'};
    unless( $code )
    {
	my $language = $args->{'language'} || $Para::Frame::REQ->language;
	$code = $language->code;
#	debug datadump $language;
    }

    if( $target =~ /\/([^\/]+)(\.\w\w)\.tt$/ )
    {
	unless( $2 eq $code )
	{
	    confess "Language mismatch ($target != $code)";
	}
    }
    else
    {
#	debug "Setting language to $code";
	$target =~ s/ \/([^\/]+)\.tt$ /\/$1.$code.tt/x;
    }

    if( my $site = $file->site )
    {
#	debug "------> SITE";
	$args->{'site'} = $site;
	$args->{'url'} = $target;
    }
    else
    {
#	debug "------> FILE";
	$args->{'filename'} = $target;
    }

    debug "TARGET $target";

    $args->{'file_may_not_exist'} = 1;

    return Para::Frame::File->new( $args );
}


#######################################################################

=head2 target_without_lang

=cut

sub target_without_lang
{
    my( $file, $args ) = @_;

    $args ||= {};

#    debug "Finding the target for ".$file->desig." with ".datadump($args,2);

    my $target = $file->{'url_norm'} || $file->{'sys_norm'};

    if( $target =~ /\/$/ )
    {
	# Target indicates a dir. Make it so
	$target .= "index.tt";
    }

    $target =~ s/\.\w\w\.tt$/.tt/;


    if( my $site = $file->site )
    {
	$args->{'site'} = $site;
	$args->{'url'} = $target;
    }
    else
    {
	$args->{'filename'} = $target;
    }

    $args->{'file_may_not_exist'} = 1;

    return Para::Frame::File->new( $args );
}


#######################################################################

=head2 template

  $f->template()

For finding the template to use for rendering the URL of C<$f>.

Uses C<dirconfig find> or L<Para::Frame::Site/find_class>.

Returns:

A L<Para::Frame::Template> object or undef

=cut

sub template
{
    my( $f ) = @_;

    # No caching allowed, dependant on REQ
    #
    #Cache within a req

    my $f2t = $Para::Frame::REQ->{'file2template'} ||= {};
    unless( $f2t->{$f} )
    {
	my $finder = $Para::Frame::REQ->dirconfig->{'find'} ||
	  $Para::Frame::REQ->site->find_class;

	if( $finder )
	{
	    debug sprintf "%s->find(%s)", $finder, $f->sysdesig;
	    return $f2t->{$f} = $finder->find($f) ||
	      Para::Frame::Template->find($f);
	}
	else
	{
#	    debug sprintf "Para::Frame::Template->find(%s)", $f->sysdesig;
	    return $f2t->{$f} = Para::Frame::Template->find($f);
	}
    }
    return $f2t->{$f};
}

#######################################################################

=head2 normalize

Removes language parts and C<index.tt> from URLs.

  $f->normalize()

If that changes the URL, returns a new L<Para::Frame::File> object,
with the flag C<may_not_exist>.

=cut

sub normalize
{
    my( $f ) = @_;

    if( my $url = $f->{'url_norm'} )
    {
	$url =~ s/\.\w\w\.tt$/.tt/;
	$url =~ s/\/index.tt$/\//;

#	if( $url =~ /Ã/ )
#	{
#	    $url = deunicode( $url );
#	    debug "Translating file to $url";
#	}

	if( $url ne $f->{'url_norm'} )
	{
	    my $args = {};
	    $args->{'url'} = $url;
	    $args->{'site'} = $f->site;
	    $args->{'file_may_not_exist'} = 1;
	    return Para::Frame::File->new($args);
	}
    }

    return $f;
}


#######################################################################

=head2 contentref

Returns a ref to a scalar with the content of the file

=cut

sub contentref
{
    my( $f ) = @_;

    unless( $f->exist )
    {
	confess "File ".$f->sysdesig." doesn't exist";
    }
    return scalar slurp( $f->sys_path_slash, scalar_ref => 1 ) ;
}


#######################################################################

=head2 content

Returns the content of the file

=cut

sub content
{
    my( $f ) = @_;

    unless( $f->exist )
    {
	confess "File ".$f->sysdesig." doesn't exist";
    }
    return scalar slurp( $f->sys_path_slash, scalar_ref => 0 ) ;
}


#######################################################################

=head2 content_as_text

Detects the charset and decodes to UTF8

Returns a ref to a scalar with the content of the file

=cut

sub contentref_as_text
{
    my( $f ) = @_;

    unless( $f->exist )
    {
	confess "File ".$f->sysdesig." doesn't exist";
    }

    require Encode::Detect::Detector;
    my $data_in = scalar(slurp( $f->sys_path_slash, scalar_ref => 0 ));
    my $charset = Encode::Detect::Detector::detect($data_in) || 'UTF-8';
    my $data = decode($charset, $data_in);

#    require Encode::Detect;
#    my $data = decode("Detect", scalar(slurp( $f->sys_path_slash, scalar_ref => 0 )));


    debug "Decoding $charset file ".$f->sysdesig;

#
#    if( utf8::is_utf8($data) )
#    {
#	if( utf8::valid($data) )
#	{
#	    debug "Marked as valid utf8";
#
#	    if( $data =~ /(V.+?lkommen|k.+?rningen)/ )
#	    {
#		my $str = $1;
#		my $len1 = length($str);
#		my $len2 = bytes::length($str);
#		debug "  >>$str ($len2/$len1)";
#	    }
#	}
#	else
#	{
#	    debug "Marked as INVALID utf8";
#	}
#    }
#    else
#    {
#	debug "NOT Marked as utf8";
#    }

    return \ $data;
}


#######################################################################

=head2 content_as_text

Detects the charset and decodes to UTF8

Returns a ref to a scalar with the content of the file

=cut

sub content_as_text
{
    my( $f ) = @_;

    unless( $f->exist )
    {
	confess "File ".$f->sysdesig." doesn't exist";
    }
    require Encode::Detect;
    return decode("Detect", scalar(slurp( $f->sys_path_slash, scalar_ref => 0 )));
}


#######################################################################

=head2 content_as_html

Detects the charset and decodes to UTF8

Returns a string with the contnet of the file, formatted as html, with
style and links

=cut

sub content_as_html
{
    my( $f, $target ) = @_;

    unless( $f->exist )
    {
	confess "File ".$f->sysdesig." doesn't exist";
    }

    require Encode::Detect;
    my $content = decode("Detect", scalar(slurp( $f->sys_path_slash, scalar_ref => 0 )));
    $target ||= $f;
    my $site = $target->site;
    my $home = $site->home->url_path;

    $content =~ s/&/&amp;/g;
    $content =~ s/</&lt;/g;
    $content =~ s/>/&gt;/g;
    $content =~ s/&lt;/<span class="html_tag">&lt;/g;
    $content =~ s/&gt;/&gt;<\/span>/g;
#    $content =~ s/\r?\n/<br>\n/g;
    $content =~ s/\[\%/<span class="tt_tag">[%/g;
    $content =~ s/\%\]/%]<\/span>/g;
#    $content =~ s/<span class="tt_tag">\[%\s*(PROCESS|INCLUDE) (.*?\.tt) %\]<\/span>/<a href="$home\/pf\/cms\/source.tt?run=find_include&page=page_path">[% $1 $2 %]<\/a>/g;
    $content =~ s/"\$home(.*?)"/"<a href="$home$1">\$home$1<\/a>"/g;
    return $content;
}


#######################################################################

=head2 copy

  $file1->copy( $file2 )

=cut

sub copy
{
    my( $f1, $f2 ) = @_;

    unless( UNIVERSAL::isa( $f2, 'Para::Frame::File' ) )
    {
	confess "Invalid param: ".datadump( $f2 );
    }

    my $f1_name = $f1->sys_path;
    my $f2_name = $f2->sys_path;

    File::Copy::copy( $f1_name, $f2_name ) or
      die "Could not copy $f1_name to $f2_name: $!";
    $f2->chmod;
    $f2->reset;
    return $f2;
}


#######################################################################

=head2 exist

  $file->exist()

Stats the file and returns true or false

=cut

sub exist
{
    my( $f ) = @_;

    my $st = stat($f->sys_path);
    if( $f->{'exist'} )
    {
	unless( $st )
	{
	    my $name = $f->sys_path;
	    debug "File $name removed from the outside!";
	    $f->{initiated} = 0;
	    $f->{'exist'} = 0;
	    return 0;
	}

	return 1;
    }
    else
    {
	if( $st )
	{
	    my $name = $f->sys_path;
	    debug "File $name created from the outside!";
	    $f->{initiated} = 0;
	    $f->{'exist'} = 1;
	    return 1;
	}
	return 0;
    }
}


#######################################################################

=head2 is_template

=cut

sub is_template
{
    return 0;
}


#######################################################################

=head2 is_dir

=cut

sub is_dir
{
    return 0;
}


#######################################################################

=head2 is_plain_file

=cut

sub is_plain_file
{
    $_[0]->initiate;
    return $_[0]->{'plain_file'};
}


#######################################################################

=head2 is_image

=cut

sub is_image
{
    return 0;
}


#######################################################################

=head2 is_readable

=cut

sub is_readable
{
    $_[0]->initiate;
    return $_[0]->{'readable'};
}


#######################################################################

=head2 mtime

  $file->mtime()

Returns a L<Para::Frame::Time> object based on the files mtime.

=cut

sub mtime
{
    $_[0]->initiate;
    return Para::Frame::Time->get($_[0]->{'mtime'});
}


#######################################################################

=head2 mtime_as_epoch

=cut

sub mtime_as_epoch
{
    $_[0]->initiate;
    return $_[0]->{'mtime'};
}


#######################################################################

=head2 utime

See perl C<utime>

=cut

sub utime
{
    my( $f, $atime_in, $mtime_in ) = @_;
    $atime_in ||= time;
    $mtime_in ||= $atime_in;

    my $atime = Para::Frame::Time->get($atime_in)->epoch;
    my $mtime = Para::Frame::Time->get($mtime_in)->epoch;

    return CORE::utime( $atime, $mtime, $f->sys_path );
}


#######################################################################

=head2 load_compiled

=cut

sub load_compiled
{
    my( $f ) = @_;

    my $compiled;
    my $filename = $f->sys_path;

    # From Template::Provider::_load_compiled:
    # load compiled template via require();  we zap any
    # %INC entry to ensure it is reloaded (we don't 
    # want 1 returned by require() to say it's in memory)
    delete $INC{ $filename };
    eval { $compiled = require $filename; };
    if( $@ )
    {
	throw('compile', "compiled template $compiled: $@");
    }
    return $compiled;
}

#######################################################################


=head2 renderer

  $f->renderer( \%args )

For gettign the renderer used for a request response, see
L<Para::Frame::Request::Response/renderer>.

The default renderer is L<Para::Frame::Renderer::TT>.

OLD: C<$renderer> should be C<undef> for using the default, or the name of
a renderer class that must have C<::Renderer::> in it's name, or a ref
in which case it's taken to be a renderer object.



Any C<%args> are given to the renderer constructor -- usually
L<Para::Frame::Renderer::TT/new>.

The C<page> arg is always set to L<$f>.

Returns a new renderer object each time it is called.

=cut

sub renderer
{
    my( $f, $args ) = @_;

    my $renderer;

    $args ||= {};

    $args->{'page'} = $f;

    return Para::Frame::Renderer::TT->new( $args );
}

#######################################################################

=head2 dirsteps

  $f->dirsteps

Returns: the current dirsteps as a ref to a list of strings.

=cut

sub dirsteps
{
    unless( $_[0]->{'dirsteps'} )
    {
	my( $f ) = @_;

	# I'ts possible ->dir returns an ordinary file. In that case,
	# fake it;
	my $path_full = $f->dir->sys_path_slash;
	$path_full =~ s/\/?$/\//; # Just in case...

	my $path_home = $f->site->home->sys_path;
	debug 3, "Setting dirsteps for $path_full";

	$f->{'dirsteps'} = [ Para::Frame::Utils::dirsteps( $path_full, $path_home ) ];
    }
    return $_[0]->{'dirsteps'};
}


#######################################################################

=head2 remove

Returns the number of files removed (1)

=cut

sub remove
{
    my( $f ) = @_;

    my $filename = $f->sys_path;
    debug "Removing file $filename";
    $f->{'exist'} = 0;
    $f->{initiated} = 0;
    if( $f->exist )
    {
	File::Remove::remove( $filename )
	    or die "Failed to remove $filename: $!";
    }
    return 1;
}


#######################################################################

=head2 as_dir

  $f->as_dir

This should be a dir. Make it so if it isn't.

Returns: the object

=cut

sub as_dir
{
    my( $f ) = @_;

    my $desig = $f->desig;
    if( ref($f) ne 'Para::Frame::File' )
    {
	confess "$desig dosen't seem to be a dir";
    }

    debug 2, "Converting $desig to a dir";

    unless( $f->exist )
    {
	$f->{'initiated'} = 0;
	my $sys_name = $f->sys_path;
	if( -r $sys_name )
	{
	    unless( -d $sys_name )
	    {
		confess "File $desig is not a dir";
	    }
	}

	$f->{'url_norm'} .= '/';
	$f->{'sys_norm'} .= '/';

	bless( $f, "Para::Frame::Dir");
	$f->initialize;
	return $f;
    }

    my $parent = $f->dir;
    my $name = $f->name . '/'; # A dir
    $f->remove;
    $f = $parent->get_virtual($name)->create();
    unless( $f->is_dir )
    {
	confess "Failed to make a dir out of $desig";
    }

    return $f;
}


#######################################################################

=head2 as_template

This should be a Template. Make it so if it isn't.

Returns the file as a template object

=cut

sub as_template
{
    my( $f ) = @_;

    my $desig = $f->sysdesig;
    if( ref($f) ne 'Para::Frame::File' )
    {
	confess "$desig dosen't seem to be a template";
    }

    debug 2, "Converting $desig to a template";

    unless( $f->exist )
    {
	my $sys_name = $f->sys_path;
	if( -r $sys_name )
	{
	    if( -d $sys_name )
	    {
		confess "File $desig is a dir";
	    }
	}
    }

    $f->{'initiated'} = 0;
    bless( $f, "Para::Frame::Template");
    $f->initialize;

    return $f;
}


#######################################################################

=head2 mimetype

=cut

sub mimetype
{
    my( $f ) = @_;

#    debug "Looking up mimetype for ".$f->desig;
    return $f->{'mimetype'} ||= File::MimeInfo::mimetype($f->sys_path_slash) || 'unknown/unknown';
}


#######################################################################

=head2 mimetype_base

=cut

sub mimetype_base
{
    my( $f ) = @_;
    $f->mimetype =~ m/(.*?)\// or
	die "No mimetype base found for ".$f->sysdesig;
    return $1;
}


#######################################################################

=head2 set_content_as_text

  $f->set_content_as_text( \$data )

Updates the file content and saves it in the file, in UTF8, starting
with a UTF8 BOM.

TODO: Convert CRLF to LF?

C<\$data> shoule be a reference to a scalar containing the new content
of the file.

Returns: true on success

=cut

sub set_content_as_text
{
    my( $f, $dataref ) = @_;

    if( $f->is_dir )
    {
	my $fname = $f->desig;
	throw('validation', "$fname is a dir");
    }

    unless( ref($dataref) and (ref $dataref eq 'SCALAR') )
    {
	throw('validation', "content not a scalar ref");
    }


    my $syspath = $f->sys_path;

    my $bom = "\x{EF}\x{BB}\x{BF}";

    debug "Storing content in file $syspath";
    open FH, ">:bytes", $syspath
      or die "Could not open $syspath for writing: $!";

#    debug validate_utf8( $dataref );
#    for( my $i=0; $i<bytes::length($$dataref); $i++ )
#    {
#	my $char = bytes::substr $$dataref, $i, 1;
#	warn sprintf "%2s %3d\n", $char, ord($char);
#    }

    unless( bytes::substr( $$dataref, 0, 3) eq $bom )
    {
	debug "  adding a BOM";
	print FH $bom;
    }

    binmode( FH, ':utf8' );
    print FH $$dataref;
    close FH;

    return 1;
}


#######################################################################

=head2 set_content

  $f->set_content( \$data )

Updates the file content and saves it in the file.

C<\$data> shoule be a reference to a scalar containing the new content
of the file.

Returns: true on success

=cut

sub set_content
{
    my( $f, $dataref ) = @_;

    if( $f->is_dir )
    {
	my $fname = $f->desig;
	throw('validation', "$fname is a dir");
    }

    unless( ref($dataref) and (ref $dataref eq 'SCALAR') )
    {
	throw('validation', "content not a scalar ref");
    }


    my $syspath = $f->sys_path;

    debug "Storing content in file $syspath";
    File::Slurp::overwrite_file($syspath, $$dataref);

    return 1;
}


#######################################################################


1;

=head1 SEE ALSO

L<Para::Frame>

=cut

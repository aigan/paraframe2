#  $Id$  -*-cperl-*-
package Para::Frame::File;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework File class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2006 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::File - Represents a file in the site

=head1 DESCRIPTION

See also L<Para::Frame::Dir> and L<Para::Frame::Page>.

=cut

use strict;
use Carp qw( croak confess cluck );
use File::stat; # exports stat
#use Scalar::Util qw(weaken);
use Number::Bytes::Human qw(format_bytes);

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump catch chmod_file create_dir );
use Para::Frame::List;
use Para::Frame::Page;
use Para::Frame::Dir;

#######################################################################

=head2 new

  Para::Frame::File->new($req)

Creates a File object. It should be initiated before used. (Done by
the methods here.)

=cut

sub new
{
    my( $this, $args ) = @_;
    my $class = ref($this) || $this;

    $args ||= {};

    my $file = bless
    {
     url_norm       => undef,
     url_name       => undef,
     site           => undef,
     initiated      => 0,
     sys_name       => undef,
     req            => undef,
     hidden         => undef,
     umask          => undef, ## defaults for files and dirs
    }, $class;

    my $no_check = $args->{no_check} || 0;


    $file->{hidden} = $args->{hidden} || qr/(^\.|^CVS$|~$)/;

    $file->{'umask'} = $args->{'umask'} || undef;

    if( my $req = $args->{req} )
    {
	$file->{req} = $req;
	weaken( $file->{'req'} );
    }

    my $sys_name = $args->{'filename'};
    my $url_in = $args->{'url'};
    if( $url_in )
    {
	if( $sys_name )
	{
	    die "Don't specify filename with uri";
	}
	elsif( UNIVERSAL::isa( $class, "Para::Frame::Dir" ) )
	{
	    $url_in =~ s/([^\/])\/?$/$1\//;
	}

#	debug datadump \@_;

	# TODO: Use URL for extracting the site
	my $site = $file->set_site( $args->{site} || $file->req->site );
	$sys_name = $site->uri2file($url_in) unless $no_check;
    }
    elsif( $sys_name and UNIVERSAL::isa( $class, "Para::Frame::Dir" ) )
    {
	$sys_name =~ s/([^\/])\/?$/$1\//;
    }
    elsif( $sys_name and (UNIVERSAL::isa( $class, "Para::Frame::File") ) )
    {
	# Ok.
    }
    else
    {
	die "Filename missing ($class): ".datadump($args);
    }

    unless( $no_check )
    {
	unless( -r $sys_name )
	{
	    confess "The file $sys_name is not found (or readable)";
	}

	if( $class eq "Para::Frame::Dir" )
	{
	    unless( -d $sys_name )
	    {
		croak "The file $sys_name is not a dir";
	    }
	}
	else
	{
	    if( -d $sys_name )
	    {
		$sys_name =~ s/([^\/])\/?$/$1\//;
		bless $file, 'Para::Frame::Dir';
	    }
	}

	$sys_name =~ s/([^\/])\/?$/$1/;
	$file->{sys_name} = $sys_name;  # Without dir trailing slash
    }

    if( my $site = $file->site )
    {
	# Check that url is part of the site
	my $home = $site->home_url_path;
	unless( $url_in =~ /^$home/ )
	{
	    confess "URL '$url_in' is out of bound for site: ".datadump($args);
	}

	my $url_name = $url_in;
	$url_name =~ s/\/$//; # Remove trailins slash

	$file->{url_norm} = $url_in;    # With dir trailing slash
	$file->{url_name} = $url_name;  # Without dir trailing slash
    }

    return $file;
}

sub site
{
    return $_[0]->{'site'};
}

sub req
{
    return $_[0]->{'req'} || $Para::Frame::REQ;
}

sub initiate
{
    my( $f ) = @_;

    my $name = $f->sys_path;
    my $mtime = (stat($name))[9];

    if( $f->{initiated} )
    {
	return 1 unless $mtime > $f->{mtime};
    }

    $f->{mtime} = $mtime;

    my $st = lstat($name);
    if( -l _ )
    {
	$f->{symbolic_link} = readlink($name);
	$st = stat($name);
    }

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

    return $f->{initiated} = 1;
}


#######################################################################

=head1 Accessors

Prefix url_ gives the path of the dir in http on the host

Prefix sys_ gives the path of the dir in the filesystem

No prefix gives the path of the dir relative the site root in url_path

path_base excludes the suffix of the filename

path_tmpl gives the path and filename

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

Gets the directory for the file.  But parent for the page C<index.tt>
or a L<Para::Frame::Dir> should be the parent dir.

Returns undef if we trying to get the parent of the
L<Para::Frame::Site/home>.

=cut


sub dir
{
    my( $f, $args ) = @_;

    $args ||= {};

    unless( $f->{'dir'} )
    {
	if( $f->site )
	{
	    my $url_path = $f->dir_url_path;
	    $f->{'dir'} = Para::Frame::Dir->new({site => $f->site,
						 url  => $url_path.'/',
						 %$args,
						});
	}
	else
	{
	    $f->sys_path =~ m/(.*)\// or return undef;
	    my $filename = $1;
	    $f->{'dir'} = Para::Frame::Dir->
	      new({
		   filename=>$filename,
		   %$args,
		  });
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
    my( $page ) = @_;
    my $template = $page->url_path_tmpl or confess "Site not given";
    $template =~ /^(.*?)\/[^\/]*$/;
    return $1||'';
}


#######################################################################

=head2 name

The template filename without the path.

For dirs, the dir name without the path.

=cut

sub name
{
    $_[0]->sys_path =~ /\/([^\/]+)\/?$/
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

    my $site = Para::Frame::Site->get( $site_in );

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
		    confess "set_site called";
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
    my( $f ) = @_;

    unless(  $f->{'sys_name'} )
    {
	$f->site or confess "Not implemented";

	my $req = $f->req;
	my $site = $f->site;
	$f->url_path =~ /(^|[^\/]+)$/ or
	  confess "fixme ".$f->url_path.' - '.datadump($f);
	my( $name ) = $1;
	my $sys_name = $site->uri2file($f->url_path_slash);
	my $safecnt = 0;
	my $umask = $f->{'umask'};# or debug "No umask for $f->{url_name}";
	while( $sys_name !~ /$name$/ )
	{
#	    debug "$sys_name doesn't end with $name";
	    die "Loop" if $safecnt++ > 100;
	    debug "Creating dir $sys_name (with umask $umask)";
	    create_dir($sys_name, {umask=>$umask});
	    $req->uri2file_clear( $f->url_path );
	    $f->{'sys_name'} = undef;
	    $f->{'orig'} = undef;
	    $sys_name = $site->uri2file($f->url_path);
#	    debug "  Now got $sys_name";
	}
#	debug sprintf "Lookup %s -> %s", $f->url_path, $sys_name;
	$f->{'sys_name'} = $sys_name;
    }

    return $f->{'sys_name'};
}


#######################################################################

=head2 sys_path_slash

The path from the system root. Including the last '/' for dirs.

# TODO; This seems wrong

=cut

sub sys_path_slash
{
    return $_[0]->sys_path . '/';
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
    $path =~ /^(.*?)(\.\w\w)?\.\w{2,3}$/
      or die "Couldn't get base from $path";
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
    my $scheme = $site->scheme;
    my $host = $site->host;
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


=head2 url_path_tmpl

The path and filename in http on the host. With the language part
removed. For L<Para::Frame::Page> this differs from L</url_path>.  For
dirs, including trailing slash.

=cut

sub url_path_tmpl
{
    return $_[0]->url_path_slash or die "No site given";
}

#######################################################################


=head2 base

The path to the template, including the filename, relative the site
home, begining with a slash. But excluding the suffixes of the file
along with the dots. For Dirs, excluding the trailing slash.

=cut

sub base
{
    my( $page ) = @_;

    my $site = $page->site or confess "No site given";
    my $home = $site->home_url_path;
    my $template = $page->url_path_tmpl;
    $template =~ /^$home(.*?)(\.\w\w)?\.\w{2,3}$/
      or die "Couldn't get base from $template under $home";
    return $1;
}


#######################################################################

#######################################################################

sub is_page
{
    return 0;
}

#######################################################################

sub is_dir
{
    return 0;
}

#######################################################################

sub chmod
{
    my( $file ) = shift;
    if( $file->can('orig') )
    {
	return chmod_file($file->orig->sys_path, @_);
    }
    else
    {
	return chmod_file($file->sys_path, @_);
    }
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
       $fh->open( $filename ) or die "Failed to open '$filename': $!\n";
       while(<$fh>)
       {
	   if( m(^\/(.+?)\/(.+?)\/) )
	   {
	       next unless $1 eq $name;
	       return $2;
	   }
       }
   }
   return undef;
}

#######################################################################

=head2 mtime

  $file->mtime()

Returns a L<Para::Frame::Time> object based on the files mtime.

=cut

sub mtime
{
   my( $file ) = @_;

   return Para::Frame::Time->get(stat($file->sys_path)->mtime);
}

#######################################################################

=head2 filesize

  $file->filesize()

=cut

sub filesize
{
   my( $file ) = @_;

   return format_bytes(stat($file->sys_path)->size);
}

#######################################################################

1;

=head1 SEE ALSO

L<Para::Frame>

=cut

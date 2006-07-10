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

Let L<Para::Frame::Dir> and L<Para::Frame::Page> inherit from this.

=cut

use strict;
use Carp qw( croak confess cluck );
use File::stat; # exports stat
#use Scalar::Util qw(weaken);

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump catch );
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

    my $url = $args->{url};
    defined $url or croak "url param missing ".datadump($args);
    $url =~ s/\/$//; # Remove trailing slash


    my $file = bless
    {
     url_name       => $url,
     site           => undef,
     initiated      => 0,
     sys_name       => undef,
     req            => undef,
    }, $class;

    if( my $req = $args->{req} )
    {
	$file->{req} = $req;
	weaken( $file->{'req'} );
    }

    # TODO: Use URL for extracting the site
    my $site = $file->set_site( $args->{site} || $file->req->site );

    # Check tat url is part of the site
    my $home = $site->home_url_path;
    unless( $url =~ /^$home/ )
    {
	confess "URL '$url' is out of bound for site: ".datadump($args);
    }

    $file->{sys_name} = $site->uri2file($url); ### Differ from dir

    unless( -r $file->{sys_name} )
    {
	croak "The file $file->{sys_name} is not found (or readable)";
    }


#    debug "Created file obj ".datadump($file);

    return $file;
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

path_tmpl gives the path and filename

path_base excludes the suffix of the filename

path gives the preffered URL for the file

For dirs: always exclude the trailing slash, except for path_slash

  url_path_tmpl  template
  url_base
  url_path       template_url url_path_full
  sys_path       sys_path_tmpl
  sys_base
  name           #filename
  base           #basename
  path_tmpl      site_url
  base           site_file
  path           path_full
  path_slash

=cut

#######################################################################

=head2 url

Returns the L<URI> object, including the scheme, host and port.

=cut

sub url
{
    my( $page ) = @_;

    my $site = $page->site;
    my $scheme = $site->scheme;
    my $host = $site->host;
    my $url_string = sprintf("%s://%s%s",
			     $site->scheme,
			     $site->host,
			     $page->{url_name});

    return Para::Frame::URI->new($url_string);
}


#######################################################################


=head2 url_path

The preffered URL for the file in http on the host. For dirs,
excluding trailing slash.


=cut

sub url_path
{
    return $_[0]->{'url_name'};
}


#######################################################################


=head2 url_path_tmpl

The path and filename in http on the host. With the language part
removed. For L<Para::Frame::Page> this differs from L</url_path>.

=cut

sub url_path_tmpl
{
    return $_[0]->url_path;
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

    my $home = $page->site->home_url_path;
    my $template = $page->url_path_tmpl;
    $template =~ /^$home(.*?)(\.\w\w)?\.\w{2,3}$/
      or die "Couldn't get base from $template under $home";
    return $1;
}


#######################################################################

=head2 parent

Same as L</dir>, except that if the template is the index, we will
instead get the parent dir.

=cut

sub parent
{
    my( $f ) = @_;

    if( $f->is_index )
    {
#	debug "Getting parent for page index";
	return $f->dir->parent;
    }
    else
    {
#	debug "Getting dir for page";
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
    my( $f ) = @_;

    unless( $f->{'dir'} )
    {
	my $url_path = $f->dir_url_path;
	$f->{'dir'} = Para::Frame::Dir->new({site => $f->site,
					     url  => $url_path,
					    });
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
    my $home = $page->site->home_url_path;
    my $template = $page->url_path_tmpl;
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
    $_[0]->url_path_tmpl =~ /\/([^\/]+)\/?$/
	or die "Couldn't get filename from ".$_[0]->url_path_tmpl;
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

    my $home = $f->site->home_url_path;
    my $url_path = $f->url_path;
    my( $site_url ) = $url_path =~ /^$home(.+?)$/
      or die "Couldn't get site_url from $url_path under $home";
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

    my $home = $f->site->home_url_path;
    my $url_path = $f->url_path_slash;
    my( $site_url ) = $url_path =~ /^$home(.+?)$/
      or die "Couldn't get site_url from $url_path under $home";
    return $site_url;
}

#######################################################################

=head2 sys_path

The path from the system root. Excluding the last '/' for dirs.

=cut

sub sys_path
{
    return $_[0]->{'sys_name'} ||= $_[0]->site->uri2file($_[0]->url_path_tmpl);
}


#######################################################################

=head2 sys_path_slash

The path from the system root. Including the last '/' for dirs.

=cut

sub sys_path_slash
{
    return $_[0]->sys_path . '/';
}


#######################################################################

=head2 site

  $f->site

Returns the L<Para::Frame::Site> this page is located in.

=cut

sub site
{
    return $_[0]->{'site'} or die;
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

    my $req = $f->req;

    $site_in or croak "site param missing";

    my $site = Para::Frame::Site->get( $site_in );

    # Check that site matches the client
    #
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

    return $f->{'site'} = $site;
}


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

1;

=head1 SEE ALSO

L<Para::Frame>

=cut

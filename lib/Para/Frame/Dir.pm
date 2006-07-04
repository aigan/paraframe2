#  $Id$  -*-cperl-*-
package Para::Frame::Dir;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Dir class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2006 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::Dir - Represents a directory in the site

=head1 DESCRIPTION

There are corresponding methods here to L<Para::Frame::Page>.

=cut

use strict;
use Carp qw( croak confess cluck );
use IO::Dir;
use File::stat; # exports stat
use Scalar::Util qw(weaken);
#use Dir::List; ### Not used...

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump catch );

our $DIR;


#######################################################################

=head2 new

  Para::Frame::Page->new($req)

Creates a Page object. It should be initiated after the request has
been registred. (Done by L<Para::Frame>.)

=cut

sub new
{
    my( $this, $args ) = @_;
    my $class = ref($this) || $this;

    $args ||= {};

    my $url = $args->{url};
    defined $url or croak "url param missing ".datadump($args);
    $url =~ s/\/$//; # Remove trailing slash

    my $site = $args->{site} ||= $Para::Frame::REQ->site;

    # Check tat url is part of the site
    my $home = $site->home;
    unless( $url =~ /^$home/ )
    {
	croak "URL '$url' is out of bound for site";
    }

    my $dir = bless
    {
     url            => $url,
     site           => $site,          ## The site for the request
     initiated      => 0,
     sys_name       => $site->uri2file($url.'/'),
    }, $class;

    unless( -r $dir->{sys_name} )
    {
	croak "The dir $dir->{sys_name} is not found (or readable)";
    }

    return $dir;
}

sub initiate
{
    return 1 if $_[0]->{initiated};

    my( $dir ) = @_;

    my %files;

    my $d = IO::Dir->new($dir->sys_name) or die $!;

    debug "Reading ".$dir->sys_name;

    while(defined( my $name = $d->read ))
    {
	next if $name =~ /^\.\.?$/;

	my $f = {};

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
#	$f->{named_pipe} = -p _;
#	$f->{socket} = -S _;
#	$f->{block_special_file} = -b _;
#	$f->{character_special_file} = -c _;
#	$f->{tty} = -t _;
#	$f->{setuid} = -u _;
#	$f->{setgid} = -g _;
#	$f->{sticky} = -k _;
	$f->{ascii} = -T _;
	$f->{binary} = -B _;

	$files{$name} = $f;
    }

    debug datadump(\%files);
    return $_[0]->{initiated} = 1;
}


#######################################################################

=head1 Accessors

Prefix url_ gives the path of the dir in http on the host

Prefix sys_ gives the path of the dir in the filesystem

No prefix gives the path of the dir relative the site root in url_path

dir excludes the trailing slash

dir_path includes the trailing slash

 # url_name
 # name
 # sys_name

=cut

#######################################################################

=head2 dirs

Returns a L<Para::Frame::List> with L<Para::Frame::Dir> objects.

=cut

sub dirs
{
    my( $dir ) = @_;

    $dir->initiate;

    my @list;
#    forach my $key
}

#######################################################################

=head2 url

Returns the L<URI> object, including the scheme, host and port.

=cut

sub url
{
    my( $dir ) = @_;

    my $site = $dir->site;
    my $scheme = $site->scheme;
    my $host = $site->host;
    my $url_string = sprintf("%s://%s%s",
			     $site->scheme,
			     $site->host,
			     $dir->name);

    return Para::Frame::URI->new($url_string);
}


#######################################################################

=head2 url_name

The URL path as a string excluding the trailing slash.

=cut

sub url_name
{
    return $_[0]->{'url'};
}


#######################################################################

=head2 url_name_path

The same as L</url_name>, but ends with a '/'.

=cut

sub url_name_path
{
    return $_[0]->{'url'} . '/';
}


#######################################################################

=head2 parent

We get the parent L<Para::Frame::Dir> object.

Returns undef if we trying to get the parent of the
L<Para::Frame::Site/home>.

=cut

sub parent
{
    my( $dir ) = @_;

    my $home = $dir->site->home;
    my( $pdirname ) = $dir->{'url'} =~ /^($home.*)\/./ or return undef;
#    die "'$pdirname','$home','$dir->{url}'" unless $pdirname;

    return $dir->new({site => $dir->site,
		      url  => $pdirname,
		     });
}


#######################################################################

=head2 name

The path to the dir, relative the L<Para::Frame::Site/home>, begining
but not ending with a slash.

=cut

sub name
{
    my( $dir ) = @_;

    my $home = $dir->site->home;
    my $url_name = $dir->url_name;
    $url_name =~ /^$home(.*)$/
      or confess "Couldn't get site_dir from $url_name under $home";
    return $1;
}

#######################################################################

=head2 name_path

The path to the dir, relative the L<Para::Frame::Site/home>, begining
and ending with a slash.

=cut

sub name_path
{
    my( $dir ) = @_;

    my $home = $dir->site->home;
    my $url_name_path = $dir->url_name_path;
    $url_name_path =~ /^$home(.*)$/
      or confess "Couldn't get site_dir from $url_name_path under $home";
    return $1;
}


#######################################################################

=head2 sys_name

The path from the system root. Excluding the last '/'

=cut

sub sys_name
{
    return $_[0]->{'sys_name'};
}


#######################################################################

=head2 sys_name_path

The path from the system root. Including the last '/'

=cut

sub sys_name_path
{
    return $_[0]->{'sys_name'} . '/';
}


#######################################################################

=head2 has_index

True if there is a (readable) C<index.tt> in this dir.

TODO: Doesn't yet check for index.xx.tt et al.

=cut

sub has_index
{
    return -r $_[0]->sys_name_path . 'index.tt';
}


#######################################################################

=head2 site

  $page->site

Returns the L<Para::Frame::Site> this page is located in.

=cut

sub site
{
    return $_[0]->{'site'} or die;
}

#######################################################################

1;

=head1 SEE ALSO

L<Para::Frame>

=cut

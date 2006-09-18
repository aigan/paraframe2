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

See also L<Para::Frame::Dir> L<Para::Frame::Site::File> and
L<Para::Frame::Page>.

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
use Para::Frame::Utils qw( throw debug datadump catch chmod_file );
use Para::Frame::List;
use Para::Frame::Page;
use Para::Frame::Nonsite::Dir;

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

    # Doesn't nbeed to check ::File
    if( $class eq 'Para::Frame::Dir' )
    {
	die "class should be Site or Nonsite";
    }

#    debug datadump $args;

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
    }, $class;

    my $no_check = $args->{no_check} || 0;


    $file->{hidden} = $args->{hidden} || qr/(^\.|^CVS$|~$)/;

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
	elsif( $class eq 'Para::Frame::File' )
	{
	    confess "class should be Site";
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
    elsif( $sys_name and ($class eq "Para::Frame::File") )
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
		bless $file, $file->dirclass;
	    }
	}

	$sys_name =~ s/([^\/])\/?$/$1/;
	$file->{sys_name} = $sys_name;  # Without dir trailing slash
    }

    return $file;
}

sub dirclass
{
    # Assume we would get class from ::Site::File otherwise
    return "Para::Frame::Nonsite::Dir";
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

Prefix sys_ gives the path of the dir in the filesystem

path_base excludes the suffix of the filename

For dirs: always exclude the trailing slash, except for path_slash

  sys_path       sys_path_tmpl
  sys_base
  name           #filename
  base           #basename

=cut

#######################################################################

=head2 parent

Same as L</dir>, except that if the template is the index, we will
instead get the parent dir.

=cut

sub parent
{
    die "not implemented";
    my( $f ) = @_;

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
    my( $f ) = @_;

    unless( $f->{'dir'} )
    {
	$f->sys_path =~ m/(.*)\// or return undef;
        my $filename = $1;
        $f->{'dir'} = Para::Frame::Nonsite::Dir->
	    new({filename=>$filename});
    }

    return $f->{'dir'};
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

# TODO; This seems wrong

=cut

sub sys_path_slash
{
    return $_[0]->sys_path . '/';
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

sub chmod
{
    return chmod_file(shift->orig->sys_path, @_);
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

1;

=head1 SEE ALSO

L<Para::Frame>

=cut

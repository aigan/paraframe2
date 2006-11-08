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
#   Copyright (C) 2006 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::Dir - Represents a directory in the site

=cut

use strict;
use Carp qw( croak confess cluck );
use IO::Dir;
use File::stat; # exports stat
use File::Remove;
use Scalar::Util qw(weaken);
#use Dir::List; ### Not used...

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use base qw( Para::Frame::File );

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump catch );
use Para::Frame::List;

=head1 DESCRIPTION

Represents a directory in the site.

See also L<Para::Frame::Site::Dir>, L<Para::Frame::File> and
L<Para::Frame::Page>.

=cut

#######################################################################

=head2 new

  Para::Frame::Dir->new(\%args)

See L<Para::Frame::File>

=cut


sub initiate
{
    my( $dir ) = @_;

    my $sys_path = $dir->sys_path;
    my $dir_st = stat($sys_path);

    unless( $dir_st )
    {
	debug "Couldn't find $sys_path!";
	$dir->{'initiated'} = 0;
	$dir->{'exist'} = 0;
	return 0;
    }

    my $mtime = $dir_st->mtime;

    if( $dir->{'initiated'} )
    {
	return 1 unless $mtime > $dir->{'mtime'};
    }

    $dir->{'mtime'} = $mtime;

    my %files;

    my $d = IO::Dir->new($sys_path) or die $!;

    debug "Reading ".$sys_path;

    while(defined( my $name = $d->read ))
    {
	next if $name =~ /^\.\.?$/;

	my $f = {};
	my $path = $sys_path.'/'.$name;

#	debug "Statting $path";
	my $st = lstat($path);
	if( -l _ )
	{
	    $f->{symbolic_link} = readlink($path);
	    $st = stat($path);
	}

	$f->{'readable'} = -r _;
	$f->{'writable'} = -w _;
	$f->{'executable'} = -x _;
	$f->{'owned'} = -o _;
	$f->{'size'} = -s _;
	$f->{'plain_file'} = -f _;
	$f->{'directory'} = -d _;
#	$f->{'named_pipe'} = -p _;
#	$f->{'socket'} = -S _;
#	$f->{'block_special_file'} = -b _;
#	$f->{'character_special_file'} = -c _;
#	$f->{'tty'} = -t _;
#	$f->{'setuid'} = -u _;
#	$f->{'setgid'} = -g _;
#	$f->{'sticky'} = -k _;
	$f->{'ascii'} = -T _;
	$f->{'binary'} = -B _;

	die "Stat failed?! ".datadump([$name, $f, $st]) unless $f->{size};

	$files{$name} = $f;
    }

    $dir->{'file'} = \%files;


    return $dir->SUPER::initiate();
}


#######################################################################

=head1 Accessors

See L<Para::Frame::File>

=cut

#######################################################################


=head2 dirs

Returns a L<Para::Frame::List> with L<Para::Frame::Dir> objects.

=cut

sub dirs
{
    my( $dir ) = @_;

    $dir->site or confess "Not implemented";

    $dir->initiate;

    my @list;
    foreach my $name ( keys %{$dir->{file}} )
    {
	next unless $dir->{file}{$name}{directory};
	my $url = $dir->{url_name}.'/'.$name;
	push @list, $dir->new({ site => $dir->site,
				url  => $url,
			      });
    }

    return Para::Frame::List->new(\@list);
}

#######################################################################

=head2 files

Returns a L<Para::Frame::List> with L<Para::Frame::File> objects.

=cut

sub files
{
    my( $dir ) = @_;

    $dir->initiate;

    my( $base, $argname );
    my $args = {};
    if( my $site = $dir->site )
    {
	$args->{'site'} = $dir->site;
	$base = $dir->url_path_slash;
	$argname = 'url';
    }
    else
    {
	$base = $dir->sys_path_slash;
	$argname = 'filename';
    }

    my @list;
    foreach my $name ( sort keys %{$dir->{'file'}} )
    {
	unless( $dir->{'file'}{$name}{'readable'} )
	{
	    debug "File $name not readable";
	    next;
	}

	next if $name =~ $dir->{'hidden'};

	$args->{$argname} = $base . $name;
	debug "Adding $name";
	if( $dir->{'file'}{$name}{'directory'} )
	{
	    debug "  As a Dir";
	    push @list, $dir->new($args);
	}
	elsif( $name =~ /\.tt$/ )
	{
	    debug "  As a Page";
	    push @list, Para::Frame::Template->new($args);
	}
	else
	{
	    debug "  As a File";
	    push @list, Para::Frame::File->new($args);
	}

	$dir->req->may_yield;
    }

    return Para::Frame::List->new(\@list);
}

#######################################################################

=head2 parent

We get the parent L<Para::Frame::Dir> object.

Returns C<undef> if we are trying to get the parent of the
L<Para::Frame::Site/home>.

If not a site file, returns undef if we are trying to get the parent
of the system root.

Returns:

 a L<Para::Frame::Dir> object

=cut

sub parent
{
    my( $dir, $args ) = @_;

    $args ||= {};

    unless( $dir->{'parent'}  )
    {
	unless( $dir->exist )
	{
	    $args->{'file_may_not_exist'} = 1;
	}

	if( my $site = $dir->site )
	{
	    my $home = $site->home_url_path;
	    my( $pdir_path ) = $dir->url_path =~ /^($home.*)\/./
	      or return undef;
	    $args->{'site'} = $site;
	    $args->{'url'} = $pdir_path.'/';
	}
	else
	{
	    my( $pdir_path ) = $dir->sys_path =~ /^(.*)\/./
	      or return undef;
	    $args->{'filename'} = $pdir_path.'/';
	}

	$dir->{'parent'} = $dir->new($args);
    }

    return $dir->{'parent'};
}


#######################################################################

=head2 has_index

True if there is a (readable) C<index.tt> in this dir.

Also handles multiple language versions.

=cut

sub has_index
{
    my( $dir ) = @_;

    my $path = $dir->sys_path_slash;

    return 1 if -r  $path . 'index.tt';

    my $language = $dir->req->language->alternatives || ['en'];
    foreach my $lang ( @$language)
    {
	my $filename = $path.'index.'.$lang.'.tt';
	return 1 if -r $filename;
    }
    return 0;
}

#######################################################################

sub is_dir
{
    return 1;
}

#######################################################################

sub has_dir
{
    my( $dir, $dir2 ) = @_;

    if( -d $dir->sys_path_slash.$dir2 )
    {
	return 1;
    }

    return 0;
}

#######################################################################

sub has_file
{
    my( $dir, $file ) = @_;

    if( -f $dir->sys_path_slash.$file)
    {
	return 1;
    }

    debug "Not found: ".$dir->sys_path_slash.$file;
    return 0;
}

#######################################################################

sub get_virtual
{
    return $_[0]->get($_[1],{'file_may_not_exist'=>1});
}

#######################################################################

sub get
{
    my( $dir, $file_in, $args ) = @_;

    $args ||= {};

    # Validate $file
    unless( $file_in =~ /^\// )
    {
	$file_in = '/'.$file_in;
    }

    unless( $dir->exist )
    {
	$args->{'file_may_not_exist'} = 1;
    }

    if( my $site = $dir->site )
    {
	my $url_str = $dir->url_path.$file_in;
	$args->{'site'} = $site;
	$args->{'url'} = $url_str;
    }
    else
    {
	my $filename = $dir->sys_path.$file_in;
	$args->{'filename'} = $filename;
    }

    return Para::Frame::File->new($args);
}

#######################################################################

sub remove
{
    my( $dir ) = @_;

    my $dirname = $dir->sys_path;
    debug "Removing dir $dirname";
    $dir->{'exist'} = 0;
    $dir->{initiated} = 0;
    File::Remove::remove( \1, $dirname )
	or die "Failed to remove $dirname: $!";
}

#######################################################################

=head2 create

  $dir->create()

  $dir->create(\%args )

Creates the directory, including parent directories.

All created dirs is chmod and chgrp to ritframe standard.

Passes C<%args> to L</create> and L</chmod>.

=cut

sub create
{
    my( $dir, $args ) = @_;

    if( $dir->exist )
    {
#	debug sprintf "Dir %s exist. Chmodding", $dir->desig;
	$dir->chmod($args);
	return $dir;
    }

    $args ||= {};
#    my $dirname = $dir->sys_path;

    $dir->parent->create($args);

    debug "Creating dir ".$dir->desig;
    mkdir $dir->sys_path, 0700 or die $!;
    $dir->{'exist'} = 1;
    $dir->{initiated} = 0;
    $dir->chmod($args);

    return $dir;
}

#######################################################################

1;

=head1 SEE ALSO

L<Para::Frame>

=cut

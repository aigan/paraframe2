package Para::Frame::Dir;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2006-2009 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Para::Frame::Dir - Represents a directory in the site

=cut

use 5.010;
use strict;
use warnings;
use base qw( Para::Frame::File );

use Carp qw( croak confess cluck longmess );
use IO::Dir;
use File::stat; # exports stat
use File::Remove;
use Scalar::Util qw(weaken);
use User::grent;
use User::pwent;

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump catch );
use Para::Frame::List;

=head1 DESCRIPTION

Represents a directory in the site.

Inherits from L<Para::Frame::File>.

=cut

##############################################################################

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
#	debug "Couldn't find dir $sys_path!";
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

    debug 2, "Reading ".$sys_path;

    while(defined( my $name = $d->read ))
    {
	next if $name =~ m/^\.\.?$/;

	my $f = {};
	my $path = $sys_path.'/'.$name;

#	debug "Statting $path";
	my $st = lstat($path);
	if( -l _ )
	{
	    $f->{symbolic_link} = readlink($path);
	    $st = stat($path);
	    # Ignore file if symlink is broken
	    next unless $st;
	}

	if( $name =~ $dir->{'hide'} )
	{
	    $f->{'hidden'} = 1;
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

	unless( $f->{'readable'} )
	{
	    my $msg = "File '$path' is not readable\n";

	    my $fu = User::pwent::getpwuid( $st->uid )
	      or die "Could not get owner of $path";
	    my $fg = User::grent::getgrgid( $st->gid )
	      or die "Could not get group of $path";
	    my $fun = $fu->name;              # file user  name
	    my $fgn = $fg->name;              # file group name
	    my $fmode = $st->mode & 07777;    # mask of filetype

	    $msg .= "  The file is owned by $fun\n";
	    $msg .= "  The file is in group $fgn\n";
	    $msg .= sprintf("  The file has mode 0%.4o\n", $fmode);

	    my $approot = $Para::Frame::CFG->{'approot'};
	    if( $approot =~ /^$sys_path\// ) # OVER approot
	    {
		debug $msg;
	    }
	    else
	    {
		$msg .= "\n".datadump([$f, $st]);
		die $msg . "\n";
	    }
	}

	$files{$name} = $f;
    }

    $dir->{'file'} = \%files;


    return $dir->SUPER::initiate();
}


##############################################################################

=head1 Accessors

See L<Para::Frame::File>

=cut

##############################################################################


=head2 dirs

Returns a L<Para::Frame::List> with L<Para::Frame::Dir> objects.

=cut

sub dirs
{
    my( $dir, $args ) = @_;

    $dir->site or confess "Not implemented";

    $dir->initiate;

    $args ||= {};
    my $include_hidden = $args->{'include_hidden'} || 0;

    my @list;
    foreach my $name ( keys %{$dir->{file}} )
    {
	next unless $dir->{file}{$name}{directory};

	unless( $include_hidden )
	{
	    next if $dir->{file}{$name}{'hidden'};
	}

	my $url = $dir->{url_name}.'/'.$name;
	push @list, $dir->new({ site => $dir->site,
				url  => $url,
			      });
    }

    return Para::Frame::List->new(\@list);
}

##############################################################################

=head2 all_files

Returns a L<Para::Frame::List> with L<Para::Frame::File> objects.  Not
skipping hidden files.

=cut

sub all_files
{
    return $_[0]->files({include_hidden=>1});
}

##############################################################################

=head2 files

Returns a L<Para::Frame::List> with L<Para::Frame::File> objects.

=cut

sub files
{
    my( $dir, $args ) = @_;

    $dir->initiate;

    $args ||= {};
    my $include_hidden = $args->{'include_hidden'} || 0;

    my( $base, $argname );
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
	my $f = $dir->{'file'}{$name};
	unless( $f->{'readable'} )
	{
	    debug "File $name not readable";
	    next;
	}

	unless( $include_hidden )
	{
	    next if $f->{'hidden'};
	}

	$args->{$argname} = $base . $name;
#	debug "Adding $name";
	if( $f->{'directory'} )
	{
#	    debug "  As a Dir";
	    push @list, $dir->new($args);
	}
	elsif( $name =~ /\.tt$/ )
	{
#	    debug "  As a Page";
	    push @list, Para::Frame::Template->new($args);
	}
	else
	{
#	    debug "  As a File";
	    push @list, Para::Frame::File->new($args);
	}

	$dir->req->may_yield;
    }

    return Para::Frame::List->new(\@list);
}

##############################################################################

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


##############################################################################

=head2 parent_sys

We get the parent L<Para::Frame::Dir> object.

Returns undef if we are trying to get the parent of the system root.

Returns:

 a L<Para::Frame::Dir> object

=cut

sub parent_sys
{
    my( $dir, $args ) = @_;

    $args ||= {};

    unless( $dir->{'parent_sys'}  )
    {
	unless( $dir->exist )
	{
	    $args->{'file_may_not_exist'} = 1;
	}

	my $parent = $dir->parent;

	my( $pdir_path ) = $dir->sys_path =~ /^(.*)\/./
	  or return undef;
	$args->{'filename'} = $pdir_path.'/';
	$dir->{'parent_sys'} = $dir->new($args);

	if( $dir->{'parent_sys'}->sys_path_slash eq
	    $parent->sys_path_slash )
	{
	    $dir->{'parent_sys'} = $parent;
	}
    }

    return $dir->{'parent_sys'};
}


##############################################################################

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

##############################################################################

=head2 is_dir

=cut

sub is_dir
{
    return 1;
}

##############################################################################

=head2 has_dir

=cut

sub has_dir
{
    my( $dir, $dir2 ) = @_;

    if( -d $dir->sys_path_slash.$dir2 )
    {
	return 1;
    }

    return 0;
}

##############################################################################

=head2 has_file

=cut

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

##############################################################################

=head2 get_virtual

  $dir->get_virtual( $filename )

Adds the arg C<file_may_not_exist> and calls L</get>.

=cut

sub get_virtual
{
    return $_[0]->get($_[1],{'file_may_not_exist'=>1});
}

##############################################################################

=head2 get_virtual_dir

  $dir->get_virtual_dir( $filename )

Adds the arg C<file_may_not_exist> and calls L</get> and calls L</as_dir>.

=cut

sub get_virtual_dir
{
    return $_[0]->get($_[1],{'file_may_not_exist'=>1})->as_dir;
}

##############################################################################

=head2 get

  $dir->get( $filename, \%args )

Possible args are

  file_may_not_exist

$filename can contain '/' for specifying a subdir. An '/' will be
added to the beginning if missing.

=cut

sub get
{
    my( $dir, $file_in, $args ) = @_;

    $args ||= {};

#    debug "Getting file $file_in from ".$dir->sysdesig;

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
#	debug "  on site ".$site->sysdesig;
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

##############################################################################

=head2 remove

Removes THIS file

Returns the number of files removed

=cut

sub remove
{
    my( $dir ) = @_;

    my $dirname = $dir->sys_path;
    debug "Removing dir $dirname";
    my $cnt = 1;

    foreach my $f ( $dir->all_files->as_array )
    {
	$cnt += $f->remove;
    }

    $dir->{'exist'} = 0;
    $dir->{initiated} = 0;

    if( $dir->exist )
    {
	# In case not all files where readable
	File::Remove::remove( \1, $dirname )
	    or die "Failed to remove $dirname: $!";
    }

    return $cnt;
}

##############################################################################

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

    $dir->initiate;
    if( $dir->exist )
    {
#	debug sprintf "Dir %s exist. Chmodding", $dir->desig;

	if( $dir->is_owned )
	{
	    # Dirs like /var chould not be chmodded
	    $dir->chmod(undef,$args);
	}
	return $dir;
    }

    $args ||= {};
    confess "Faulty args given" unless ref $args;

    my $dirname = $dir->sys_path;
#    debug "  creating $dirname";

    $dir->parent_sys->create($args);

#    debug "Creating dir ".$dir->desig;
    mkdir $dir->sys_path, 0700 or
      die sprintf "Failed to make dir %s: %s\n%s", $dir->sys_path, $!, longmess();
    $dir->{'exist'} = 1;
    $dir->{initiated} = 0;
    $dir->chmod(undef,$args);

    return $dir;
}

##############################################################################

=head2 as_dir

  $f->as_dir

See also L<Para::Frame::File/as_dir>

Returns: the object

=cut

sub as_dir
{
    return $_[0];
}

##############################################################################

1;

=head1 SEE ALSO

L<Para::Frame>

=cut

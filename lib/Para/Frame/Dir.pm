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
use Scalar::Util qw(weaken);
#use Dir::List; ### Not used...

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use base 'Para::Frame::File';

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump catch );
use Para::Frame::List;
use Para::Frame::Page;

=head1 DESCRIPTION

Represents a directory in the site.

This class inherits from L<Para::Frame::File>.

There are corresponding methods here to L<Para::Frame::Page>.

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
    my $mtime = (stat($sys_path))[9];
    if( $dir->{initiated} )
    {
	return 1 unless $mtime > $dir->{mtime};
    }

    $dir->{mtime} = $mtime;

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

	die "Stat failed?! ".datadump([$f, $st]) unless $f->{size};

	$files{$name} = $f;
    }

    $dir->{file} = \%files;

    return $dir->{initiated} = 1;
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

    debug "Called dir.files";
    $dir->initiate;

    debug "Directory initiated";

    my @list;
    foreach my $name ( sort keys %{$dir->{file}} )
    {
	unless( $dir->{file}{$name}{readable} )
	{
	    debug "File $name not readable";
	    next;
	}

	next if $name =~ $dir->{hidden};

	my $url = $dir->{url_name}.'/'.$name;
	debug "Adding $url";
	if( $dir->{file}{$name}{directory} )
	{
	    debug "  As a Dir";
	    push @list, $dir->new({ site => $dir->site,
				    url  => $url.'/',
				  });
	}
	elsif( $name =~ /\.tt$/ )
	{
	    debug "  As a Page";
	    push @list, Para::Frame::Page->new({ site => $dir->site,
						 url  => $url,
					       });
	}
	else
	{
	    debug "  As a File";
	    push @list, Para::Frame::File->new({ site => $dir->site,
						 url  => $url,
					       });
	}
    }

    return Para::Frame::List->new(\@list);
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

    my $home = $dir->site->home_url_path;
    my( $pdirname ) = $dir->{'url_name'} =~ /^($home.*)\/./ or return undef;

    return $dir->new({site => $dir->site,
		      url  => $pdirname.'/',
		     });
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

1;

=head1 SEE ALSO

L<Para::Frame>

=cut

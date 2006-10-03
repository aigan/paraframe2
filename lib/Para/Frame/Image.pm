#  $Id$  -*-cperl-*-
package Para::Frame::Image;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Image class
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

Para::Frame::Image - Represents an image file

=head1 DESCRIPTION

See also L<Para::Frame::File>

=cut

use strict;
use Carp qw( croak confess cluck );
#use File::stat; # exports stat
#use Scalar::Util qw(weaken);
use Image::Magick;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use base qw( Para::Frame::File );

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump catch );

#######################################################################

sub magick
{
    my( $img ) = @_;

    unless( $img->{'magick'} )
    {
	my $im = new Image::Magick;
	$im->Read($img->sys_path);
	$img->{'magick'} = $im;
    }
    return $img->{'magick'};
}

sub reset
{
    my( $img ) =@_;

    delete $img->{'magick'};
}

sub clone
{
    return $_[0]->new({filename=>$_[0]->sys_path});
}

sub width
{
    return $_[0]->magick->Get('width');
}

sub height
{
    return $_[0]->magick->Get('height');
}

sub resize_normal
{
    return $_[0]->resize({
			  x => 700,
			  y => 525,
			  q => 75,
			  t => 'n',
			 });
}

sub resize_thumb
{
    return $_[0]->resize_thumb_y;
}

sub resize_thumb_y
{
    return $_[0]->resize({
			  y => 150,
			  q => 30,
			  t => 't',
			 });
}
sub resize_thumb_x
{
    return $_[0]->resize({
			  x => 200,
			  q => 30,
			  t => 'tx',
			 });
}

sub resize
{
    my( $img, $arg ) = @_;

    my $im = $img->magick;
    my $x = $img->width;
    my $y = $img->height;

    my $xm = $arg->{'x'};
    my $ym = $arg->{'y'};
    my $quality = $arg->{'q'};

    my( $xn, $yn );

    if( $xm )
    {
	$xn = $xm;
	$yn = int( $xn * $y / $x );
	if( $ym and ($yn > $ym) )
	{
	    $yn = $ym;
	    $xn = int( $yn * $x / $y );
	}
    }
    elsif( $ym )
    {
	$yn = $ym;
	$xn = int( $yn * $x / $y );
	if( $xm and ($xn > $xm) )
	{
	    $xn = $xm;
	    $yn = int( $xn * $y / $x );
	}
    }
    else
    {
	die "Neither x nor y specified: ".datadump($arg);
    }

    $im->Thumbnail(width=>$xn, height=>$yn);

    my $tag = $arg->{'t'} or die "Tag missing: ".datadump($arg);
    my $filename_new = $img->sys_base . "-$tag.jpg";
    $im->Write(filename=>"$filename_new", quality=>$quality );
    $img->reset;
    my $new = $_[0]->new({filename=>$filename_new});
    $new->chmod({umask=>02});
    return $new;
}

sub save_as
{
    my( $img, $filename_new, $arg ) = @_;

    my $quality = $arg->{'q'} || 75;
    $img->magick->Write(filename=>$filename_new, quality=>$quality );
    my $new = $_[0]->new({filename=>$filename_new});
    $new->chmod({umask=>02});
    return $new;
}

sub sys_base
{
    my $base = $_[0]->SUPER::sys_base;
    $base =~ s/-\w+$//;
    return $base;
}

sub rotate
{
    my( $img, $deg ) = @_;

    my $im = $img->magick;

    $im->Rotate(degrees=>$deg, color=>'black');
    return $img->commit;
}

sub commit
{
    my( $img ) = @_;

    $img->magick->Write(filename=>$img->sys_path);
    $img->chmod({umask=>02});
    return $img;
}


#######################################################################

1;

=head1 SEE ALSO

L<Para::Frame>

=cut

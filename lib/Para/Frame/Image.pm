package Para::Frame::Image;
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

Para::Frame::Image - Represents an image file

=head1 DESCRIPTION

See also L<Para::Frame::File>

=cut

use 5.010;
use strict;
use warnings;

use Carp qw( croak confess cluck );
use Image::Magick;

use base qw( Para::Frame::File );

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump catch );

##############################################################################

=head2 magick

=cut

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


##############################################################################

=head2 reset

=cut

sub reset
{
    my( $img ) =@_;

    delete $img->{'magick'};
}


##############################################################################

=head2 clone

=cut

sub clone
{
    return $_[0]->new({filename=>$_[0]->sys_path});
}


##############################################################################

=head2 width

=cut

sub width
{
    return $_[0]->magick->Get('width');
}


##############################################################################

=head2 height

=cut

sub height
{
    return $_[0]->magick->Get('height');
}


##############################################################################

=head2 resize_normal

=cut

sub resize_normal
{
    return $_[0]->resize({
			  x => 700,
			  y => 525,
			  q => 75,
			  t => 'n',
			 });
}


##############################################################################

=head2 resize_thumb

=cut

sub resize_thumb
{
    return $_[0]->resize_thumb_y;
}


##############################################################################

=head2 resize_thumb_y

=cut

sub resize_thumb_y
{
    return $_[0]->resize({
			  y => 150,
			  q => 30,
			  t => 't',
			 });
}


##############################################################################

=head2 resoze_thumb_x

=cut

sub resize_thumb_x
{
    return $_[0]->resize({
			  x => 200,
			  q => 30,
			  t => 'tx',
			 });
}


##############################################################################

=head2 resize

=cut

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


##############################################################################

=head2 save_as

=cut

sub save_as
{
    my( $img, $filename_new, $arg ) = @_;

    my $quality = $arg->{'q'} || 75;
    $img->magick->Write(filename=>$filename_new, quality=>$quality );
    my $new = $_[0]->new({filename=>$filename_new});
    $new->chmod({umask=>02});
    return $new;
}


##############################################################################

=head2 sys_base

=cut

sub sys_base
{
    my $base = $_[0]->SUPER::sys_base;
    $base =~ s/-\w+$//;
    return $base;
}


##############################################################################

=head2 rotate

=cut

sub rotate
{
    my( $img, $deg ) = @_;

    my $im = $img->magick;

    $im->Rotate(degrees=>$deg, color=>'black');
    return $img->commit;
}


##############################################################################

=head2 commit

=cut

sub commit
{
    my( $img ) = @_;

    $img->magick->Write(filename=>$img->sys_path);
    $img->chmod({umask=>02});
    return $img;
}


##############################################################################

=head2 is_image

=cut

sub is_image
{
    return 1;
}

##############################################################################

1;

=head1 SEE ALSO

L<Para::Frame>

=cut

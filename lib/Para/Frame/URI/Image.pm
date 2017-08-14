package Para::Frame::URI::Image;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2014-2017 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Para::Frame::URI::Image - Represents an image URL

=head1 DESCRIPTION

See also L<Para::Frame::URI>

=cut

use 5.012;
use warnings;

use Carp qw( croak confess cluck );

use base qw( Para::Frame::URI );

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump catch );

##############################################################################

=head2 as_html

=cut

sub as_html
{
    my( $url, $attrs ) = @_;

    return "" unless $url->{'value'};

    $attrs ||= {};

    my $href = $url->{'value'}->as_string;

    my $out = sprintf '<img src="%s">', $href;

    return $out;
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

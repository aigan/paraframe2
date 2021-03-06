package Para::Frame::Email::Address::Fallback;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2017 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Para::Frame::Email::Address::Fallback  - Represents a broken email address

=cut

use 5.012;
use warnings;

use Para::Frame::Reload;

=head1 DESCRIPTION

Used for broken addresses or addresses that L<Mail::Address> can't
parse. Used by L<Para::Frame::Email::Address>.

=cut


##############################################################################

=head2 parse

  $a->parse( $string )

Returns an object that acts as an alternative to L<Mail::Address>

=cut

sub parse
{
    return bless
    {
     string => $_[1],
    }, $_[0];
}


##############################################################################

=head2 address

=cut

sub address
{
    return $_[0]->{'string'};
}


##############################################################################

=head2 user

=cut

sub user { "" }


##############################################################################

=head2 host

=cut

sub host { "" }


##############################################################################

=head2 format

=cut

sub format { $_[0]->{string} }


##############################################################################

=head2 format_human

=cut

sub format_human { $_[0]->{string} }


##############################################################################

=head2 name

=cut

sub name
{
    return "";
}


##############################################################################

=head2 phrase

=cut

sub phrase
{
    return "";
}


##############################################################################

=head2 comment

=cut

sub comment
{
    return "";
}


######################################################################

1;

=head1 SEE ALSO

L<Para::Frame::Email::Address>, L<Mail::Address>

=cut

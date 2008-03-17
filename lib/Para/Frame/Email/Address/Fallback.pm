#  $Id$  -*-cperl-*-
package Para::Frame::Email::Address::Fallback;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2008 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::Email::Address::Fallback  - Represents a broken email address

=cut

use strict;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;

=head1 DESCRIPTION

Used for broken addresses or addresses that L<Mail::Address> can't
parse. Used by L<Para::Frame::Email::Address>.

=cut


#######################################################################

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


#######################################################################

=head2 address

=cut

sub address
{
    return $_[0]->{'string'};
}


#######################################################################

=head2 user

=cut

sub user { "" }


#######################################################################

=head2 host

=cut

sub host { "" }


#######################################################################

=head2 format

=cut

sub format { $_[0]->{string} }


#######################################################################

=head2 name

=cut

sub name
{
    return "";
}


######################################################################

1;

=head1 SEE ALSO

L<Para::Frame::Email::Address>, L<Mail::Address>

=cut

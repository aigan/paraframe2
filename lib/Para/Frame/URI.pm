#  $Id$  -*-cperl-*-
package Para::Frame::URI;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework URI class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2006 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::URI - Represent an URI

=cut

use strict;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}


#######################################################################

=head2 new

  URI->new($uri, $scheme)

Returns a L<URI> object, but may be modified to suit paraframe.

=cut

sub new
{
    my( $class, $uri, $scheme ) = @_;

    $uri = defined ($uri) ? "$uri" : "";   # stringify

    # Remove double / in path

    $uri =~ s§([^:])//+§$1/§g;

    return URI->new($uri, $scheme);
}

#######################################################################

1;


=head1 AUTHOR

Jonas Liljegren E<lt>jonas@paranormal.seE<gt>

=head1 SEE ALSO

L<Para::Frame>, L<URI>

=cut

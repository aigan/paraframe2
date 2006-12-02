#  $Id$  -*-cperl-*-
package Para::Frame::Template::Compiled;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework Compiled Template class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2006 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::Template::Compiled - Represents a perl-compiled Template file

=cut

use strict;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;

use base qw( Para::Frame::File );


#######################################################################

1;

=head1 SEE ALSO

L<Para::Frame>

=cut

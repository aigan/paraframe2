#  $Id$  -*-perl-*-
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
#   Copyright (C) 2005 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

sub new
{
    my( $class, $uri, $scheme ) = @_;

    $uri = defined ($uri) ? "$uri" : "";   # stringify

    # Remove double / in path

    $uri =~ s§//§/§g;

    return URI->new($uri, $scheme);
}

1;

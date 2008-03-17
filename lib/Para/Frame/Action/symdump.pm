#  $Id$  -*-cperl-*-
package Para::Frame::Action::symdump;
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

use strict;
use Devel::Symdump;

=head1 DESCRIPTION

Paranormal.se symdump debug

=cut

sub handler
{
    my( $req ) = @_;

    my $newdump = Devel::Symdump->rnew;
    warn $Para::symdump->diff($newdump)."\n";
    $Para::symdump = $newdump;

    return "Sent symdump to STDERR";
}

1;

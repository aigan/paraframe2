#  $Id$  -*-perl-*-
package Para::Frame::Action::user_logout;
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

use Para::Frame::Route;


=head1 NAME

Para::Frame::Action::user_logou - For logging out

=cut

sub handler
{
    my( $req ) = @_;

    $Para::Frame::U->logout;

    # Not to be used after a logout
    &Para::Frame::Route::clear_special_params;

    return "Du har nu loggat ut\n";
}

1;

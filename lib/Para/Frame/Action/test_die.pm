package Para::Frame::Action::test_die;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2022 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.012;
use warnings;

use Para::Frame::Utils qw( debug );

# For testing purposes

sub handler
{
    my( $req ) = @_;

		debug "Suicide";
		exit 33;
}

1;

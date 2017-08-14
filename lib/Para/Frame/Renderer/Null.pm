package Para::Frame::Renderer::Null;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2015-2017 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.012;
use warnings;

use base 'Para::Frame::Renderer::Custom';

sub render_output
{
    return \"";
}

1;
